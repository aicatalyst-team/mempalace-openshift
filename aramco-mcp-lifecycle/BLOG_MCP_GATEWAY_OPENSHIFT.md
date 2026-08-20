# Deploy and federate MCP servers on OpenShift AI with the MCP Lifecycle Operator and MCP Gateway

**Who should read this:** Platform engineers, AI/ML engineers and SREs running OpenShift AI who need to deploy and manage MCP (Model Context Protocol) servers at scale. Familiarity with OpenShift and Kubernetes Gateway API is assumed.

**What you'll learn:**
- How to deploy an MCP server declaratively using the MCP Lifecycle Operator and the `MCPServer` custom resource
- How to register that server behind the MCP Gateway for tool federation, discovery and routing
- Key configuration details for the OpenShift AI `data-science-gateway-class` that differ from upstream Kuadrant documentation
- How the ext_proc routing architecture works for `tools/call` requests

## The problem

You have an AI tool server that speaks MCP. You can run it locally, but deploying it to a shared OpenShift AI cluster and making its tools available to multiple AI agents introduces real operational questions: How do you manage the server lifecycle? How do agents discover which tools exist? How do you route tool calls to the right backend when you have dozens of MCP servers?

Manual `Deployment` + `Service` manifests work for one server. They do not scale to ten. The MCP Lifecycle Operator and MCP Gateway solve this by giving you a declarative, Kubernetes-native way to deploy MCP servers and federate their tools behind a single gateway endpoint.

This article walks through deploying [MemPalace](https://github.com/anthropics/mempalace)---an AI memory system with 29 MCP tools---on OpenShift AI 3.4.2, using the MCP Lifecycle Operator to manage the server and the MCP Gateway to federate its tools.

## Architecture overview

The deployment involves three operator-managed layers:

```
AI Agent / Client
       |
       | POST /mcp (tools/call, tools/list, initialize)
       v
+------------------+
| MCP Gateway      |  <-- Envoy + ext_proc router + broker
| (Kuadrant)       |      Tool discovery, session management,
|                  |      prefix-based routing
+------------------+
       |
       | ext_proc rewrites :authority header
       | routes tools/call directly to backend via Envoy
       v
+------------------+
| MemPalace        |  <-- Managed by MCP Lifecycle Operator
| MCPServer CR     |      Streamable HTTP transport (POST /mcp)
| 29 tools         |      Health probes, resource limits, storage
+------------------+
```

**MCP Lifecycle Operator** (kubernetes-sigs, v0.2.0): Watches `MCPServer` custom resources. For each one, it creates a `Deployment`, `Service` and performs an MCP protocol handshake to verify the server speaks MCP correctly before marking it `Ready`.

**MCP Gateway Operator** (Kuadrant, v0.7.1, Tech Preview): Deploys an Envoy-based gateway with a broker component and an ext_proc router. The broker discovers tools from registered upstream MCP servers. The router intercepts `tools/call` requests and rewrites Envoy's `:authority` header to route them directly to the correct backend---the broker never proxies tool call payloads.

## Prerequisites

- OpenShift AI 3.4.2+ cluster with the `data-science-gateway-class` GatewayClass available
- MCP Lifecycle Operator installed (from OperatorHub or YAML manifests)
- MCP Gateway Operator installed (from Red Hat Operators catalog, `rhcl-tech-preview` channel)
- A container image for your MCP server that supports streamable HTTP transport (POST `/mcp`)
- `oc` CLI authenticated to the cluster

## Step 1: Prepare the MCP server image

The MCP Lifecycle Operator requires servers to support **MCP streamable HTTP transport**---the standard `POST /mcp` endpoint with JSON-RPC 2.0. WebSocket-only servers will not pass the operator's handshake.

For MemPalace, this meant adding a FastAPI-based HTTP transport layer:

```python
@app.post("/mcp")
async def mcp_streamable_http(request: Request):
    """MCP streamable HTTP transport endpoint."""
    body = await request.json()
    session_id = request.headers.get("mcp-session-id")

    is_batch = isinstance(body, list)
    requests = body if is_batch else [body]
    responses = []

    for rpc_request in requests:
        response = await asyncio.to_thread(handle_request, rpc_request)
        if rpc_request.get("method") == "initialize" and response:
            session_id = str(uuid.uuid4())
        if response is not None:
            responses.append(response)

    if not responses:
        return Response(status_code=202)

    result = responses if is_batch else responses[0]
    headers = {"mcp-session-id": session_id} if session_id else {}
    return JSONResponse(content=result, headers=headers)
```

The `tools/list` response must include `_meta.id` and `annotations` fields for MCP Gateway compatibility:

```python
{
    "name": "mempalace_status",
    "description": "Palace overview",
    "inputSchema": {"type": "object", "properties": {}},
    "_meta": {"id": "mempalace_status"},
    "annotations": {}
}
```

Build and push the image using a UBI 9 base for OpenShift compatibility:

```bash
podman build --platform linux/amd64 \
  -f Dockerfile.ubi \
  -t quay.io/aicatalyst/mempalace:operator-v2 .

podman push quay.io/aicatalyst/mempalace:operator-v2
```

## Step 2: Deploy via the MCPServer custom resource

Create the namespace and deploy the server using the MCP Lifecycle Operator:

```bash
oc new-project mempalace
```

Apply the `MCPServer` CR:

```yaml
apiVersion: mcp.x-k8s.io/v1alpha1
kind: MCPServer
metadata:
  name: mempalace
  namespace: mempalace
spec:
  source:
    type: ContainerImage
    containerImage:
      ref: quay.io/aicatalyst/mempalace:operator-v2
  config:
    port: 8000
    path: /mcp
    arguments:
    - "--transport"
    - "streamable-http"
    - "--host"
    - "0.0.0.0"
    - "--port"
    - "8000"
    - "--palace"
    - "/opt/app-root/data"
    env:
    - name: MEMPALACE_HOME
      value: /opt/app-root/data
    - name: PYTHONUNBUFFERED
      value: "1"
    storage:
    - path: /opt/app-root/data
      permissions: ReadWrite
      source:
        type: EmptyDir
        emptyDir:
          sizeLimit: 10Gi
  runtime:
    replicas: 1
    resources:
      requests:
        memory: "2Gi"
        cpu: "500m"
      limits:
        memory: "4Gi"
        cpu: "2000m"
    health:
      livenessProbe:
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 30
        periodSeconds: 10
      readinessProbe:
        httpGet:
          path: /ready
          port: 8000
        initialDelaySeconds: 10
        periodSeconds: 5
  mcp:
    stateless: false
```

The operator creates a `Deployment` and `Service`, then performs an MCP handshake:

```
$ oc get mcpserver mempalace -n mempalace -o jsonpath='{.status}' | python3 -m json.tool
{
    "address": {
        "url": "http://mempalace.mempalace.svc.cluster.local:8000/mcp"
    },
    "conditions": [
        {
            "message": "Configuration is valid",
            "reason": "Valid",
            "status": "True",
            "type": "Accepted"
        },
        {
            "message": "MCP server is ready (1 of 1 instances healthy)",
            "reason": "Available",
            "status": "True",
            "type": "Ready"
        }
    ],
    "serverInfo": {
        "capabilities": {"tools": true},
        "name": "mempalace",
        "protocolVersion": "2025-11-25",
        "version": "3.3.3"
    }
}
```

The operator verified: the server speaks MCP protocol version `2025-11-25`, exposes tool capabilities and is running version `3.3.3`. No manual health check wiring required.

## Step 3: Set up the MCP Gateway

The MCP Gateway requires three resources: a `Gateway`, an `MCPGatewayExtension` and an `EnvoyFilter` (created automatically by the controller).

### Create the gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: mcp-gateway
  namespace: mcp-gateway-system
spec:
  gatewayClassName: data-science-gateway-class
  listeners:
  - name: mcp
    port: 8443
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            mcp-gateway-access: "true"
```

> **OpenShift AI-specific:** Do **not** set a `hostname` on the gateway listener. If you do, all HTTPRoutes must use the same hostname, which breaks the ext_proc router's ability to differentiate backend routes from broker routes (see "How routing works" below). Use `publicHost` on the `MCPGatewayExtension` instead.

### Extend the gateway with MCP protocol support

```yaml
apiVersion: mcp.kuadrant.io/v1alpha1
kind: MCPGatewayExtension
metadata:
  name: mcp-gateway-extension
  namespace: mcp-gateway-system
spec:
  publicHost: mcp-gateway.apps.ocp-gb.ibm.redhataicatalyst.com
  privateHost: mcp-gateway-data-science-gateway-class.mcp-gateway-system.svc.cluster.local:8443
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: mcp-gateway
    namespace: mcp-gateway-system
    sectionName: mcp
```

The `privateHost` is the cluster-internal address of the Envoy proxy. The controller uses it for hairpin routing during tool discovery. The naming pattern is `mcp-gateway-<gatewayClassName>.<namespace>.svc.cluster.local:<port>`.

### Label the namespace for cross-namespace routing

```bash
oc label namespace mempalace mcp-gateway-access=true
```

## Step 4: Register the MCP server behind the gateway

Create an `HTTPRoute` and `MCPServerRegistration` to wire the backend to the gateway. The HTTPRoute hostname is a **routing marker**---the ext_proc router uses it to set the `:authority` header, so Envoy routes `tools/call` requests directly to the backend. It is not a DNS name.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mempalace-mcp-route
  namespace: mcp-gateway-system
spec:
  hostnames:
  - mempalace-backend  # routing marker, not DNS
  parentRefs:
  - name: mcp-gateway
    namespace: mcp-gateway-system
    sectionName: mcp
  rules:
  - backendRefs:
    - name: mempalace
      namespace: mempalace
      port: 8000
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-mcp-gateway
  namespace: mempalace
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: mcp-gateway-system
  to:
  - group: ""
    kind: Service
---
apiVersion: mcp.kuadrant.io/v1alpha1
kind: MCPServerRegistration
metadata:
  name: mempalace
  namespace: mcp-gateway-system
spec:
  prefix: mempalace_
  hint: "AI memory system with semantic search"
  category:
  - memory
  - knowledge-management
  tags:
  - ai-memory
  - semantic-search
  path: /mcp
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: mempalace-mcp-route
```

Verify registration:

```
$ oc get mcpserverregistration mempalace -n mcp-gateway-system
NAME        READY   TOOLS   AGE
mempalace   True    29      10m
```

The broker discovered all 29 MemPalace tools and federated them with the `mempalace_` prefix.

## Step 5: Test end-to-end tool calls

Initialize an MCP session through the gateway:

```bash
curl -s -D - -X POST "http://<gateway-external-address>:8443/mcp" \
  -H "Host: mcp-gateway.apps.ocp-gb.ibm.redhataicatalyst.com" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-03-26",
      "capabilities": {},
      "clientInfo": {"name": "test-client", "version": "1.0"}
    }
  }'
```

The gateway returns its identity and a session token:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-03-26",
    "capabilities": {
      "prompts": {"listChanged": true},
      "tools": {"listChanged": true}
    },
    "serverInfo": {
      "name": "Kuadrant MCP Gateway",
      "version": "0.0.1"
    }
  }
}
```

Discover available tools using the gateway's built-in `discover_tools` meta-tool:

```bash
curl -s -X POST "http://<gateway-external-address>:8443/mcp" \
  -H "Host: mcp-gateway.apps.ocp-gb.ibm.redhataicatalyst.com" \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: <session-id-from-initialize>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "discover_tools",
      "arguments": {}
    }
  }'
```

The response shows MemPalace registered with all 29 tools:

```json
{
  "servers": [{
    "name": "mcp-gateway-system/mempalace",
    "categories": ["memory", "knowledge-management"],
    "hint": "AI memory system with semantic search",
    "tools": [
      "mempalace_mempalace_status",
      "mempalace_mempalace_search",
      "mempalace_mempalace_add_drawer",
      "mempalace_mempalace_list_wings",
      "..."
    ]
  }]
}
```

Call a tool through the gateway:

```bash
curl -s -X POST "http://<gateway-external-address>:8443/mcp" \
  -H "Host: mcp-gateway.apps.ocp-gb.ibm.redhataicatalyst.com" \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: <session-id>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "mempalace_mempalace_status",
      "arguments": {}
    }
  }'
```

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [{
      "type": "text",
      "text": "{\"palace\": \"mempalace\", \"wings\": 1, \"rooms\": 1, \"drawers\": 0}"
    }]
  }
}
```

The response came directly from the MemPalace backend (`server: uvicorn` in the response headers)---the gateway's ext_proc router sent the request to the backend, not through the broker.

## How routing works

Understanding the routing architecture is critical for debugging. The MCP Gateway uses three components:

1. **Envoy proxy** (istio-proxy): Receives all external traffic on port 8443
2. **ext_proc router** (gRPC on port 50051): Intercepts requests, parses MCP method from the body, decides routing
3. **Broker** (HTTP on port 8080): Handles `initialize`, `tools/list`, `discover_tools` and other non-tool-call methods

For `initialize` and `tools/list`, the router sets `:authority` to the gateway's public hostname, and Envoy routes to the broker. For `tools/call`, the router:

1. Parses the tool name from the JSON body (e.g., `mempalace_mempalace_status`)
2. Looks up the tool in the routing table
3. Strips the registration prefix (`mempalace_`) to get the upstream tool name (`mempalace_status`)
4. Rewrites the body with the upstream name
5. Sets `:authority` to the backend's HTTPRoute hostname (`mempalace-backend`)
6. Clears the Envoy route cache
7. Envoy re-evaluates routing and sends the request directly to the MemPalace service

This is why the HTTPRoute hostname **must differ** from the gateway's public hostname. If they match, Envoy cannot distinguish broker-bound traffic from backend-bound traffic.

## Troubleshooting

**"listener has no hostname and spec.publicHost is not set"** on MCPGatewayExtension: Set `publicHost` on the MCPGatewayExtension spec. Do not add a hostname to the gateway listener.

**"tool not found" on tools/call but tools/list works:** The HTTPRoute for the backend has the same hostname as the gateway's broker route. Change it to a unique routing marker (e.g., `myserver-backend`).

**"unable to check conflict, tool id is missing" in broker logs:** Your MCP server's `tools/list` response is missing `_meta` and `annotations` fields on each tool. These are logged at ERROR level but do not block tool registration---the broker registers tools regardless. The conflict check (which uses `kuadrant/id` in the tool meta) is only relevant when multiple registrations serve tools with the same name.

**"no such host" errors from the broker:** The `privateHost` on MCPGatewayExtension is wrong. It must match the Envoy proxy service name exactly: `mcp-gateway-<gatewayClassName>.<namespace>.svc.cluster.local:<port>`.

## What's next

With the MCP server deployed and federated, you can:

- Register additional MCP servers behind the same gateway---each gets its own prefix and routing
- Connect AI agents to the gateway's single `/mcp` endpoint for unified tool access
- Add authentication via Kuadrant `AuthPolicy` (OIDC, API key)
- Scale the MCP server by increasing `runtime.replicas` in the `MCPServer` CR
- Replace EmptyDir storage with a PersistentVolumeClaim for production data durability

The MCP Lifecycle Operator and MCP Gateway bring the same declarative, operator-managed approach to MCP servers that OpenShift AI brings to model serving. Instead of managing deployments and routing by hand, you declare what you want---the operators handle the rest.

**Try it yourself:** The complete manifests are available in the [MemPalace repository](https://github.com/anthropics/mempalace/tree/main/openshift). Start with the `MCPServer` CR and add the gateway when you need multi-server federation.

---

*Gerald Trotman is a Senior Specialist Solution Architect at Red Hat, focusing on AI/ML platform engineering.*
