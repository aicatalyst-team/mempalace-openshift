# MCP Server Lifecycle on OpenShift AI — Demo Runbook

**Audience:** Customer who already runs MCP servers and wants to understand the production lifecycle on Red Hat's OpenShift AI stack.

**Setup:** Terminal with `oc` authenticated to the cluster. Run each block manually, explain the value between steps.

**Cluster:** `api.ocp-gb.ibm.redhataicatalyst.com:6443`  
**Gateway:** `http://06536a44-eu-gb.lb.appdomain.cloud:8443`

---

## Before You Start

```bash
# Authenticate (get a fresh token from the OpenShift console)
oc login --token=sha256~<TOKEN> --server=https://api.ocp-gb.ibm.redhataicatalyst.com:6443

# Verify
oc whoami
oc version | head -3
```

### Clean up test drawers (optional, for a fresh demo)

```bash
# Check current drawer count
GATEWAY="http://06536a44-eu-gb.lb.appdomain.cloud:8443"
HOST="mcp-gateway.apps.ocp-gb.ibm.redhataicatalyst.com"

# Quick status check directly on the pod
oc exec -n mempalace deploy/mempalace -- python3 -c '
import urllib.request, json
req = urllib.request.Request("http://localhost:8000/mcp",
    data=json.dumps({"jsonrpc":"2.0","id":1,"method":"tools/call",
    "params":{"name":"mempalace_status","arguments":{}}}).encode(),
    headers={"Content-Type":"application/json"})
r = json.loads(urllib.request.urlopen(req).read())
s = json.loads(r["result"]["content"][0]["text"])
print(f"Drawers: {s[\"total_drawers\"]}, Wings: {s[\"wings\"]}, Rooms: {s[\"rooms\"]}")
'
```

---

## Phase 1: The Platform

> **What to say:** "You've built MCP servers that work locally. The question is: how do you get them into production with the same operational rigor as the rest of your platform? On OpenShift AI, two operators handle this."

```bash
# The cluster
oc whoami
oc version | head -3
```

```bash
# MCP Gateway Operator — Kuadrant, Tech Preview, manages the gateway
oc get csv -n mcp-gateway-system mcp-gateway.v0.7.1 \
  -o custom-columns=NAME:.spec.displayName,VERSION:.spec.version,STATUS:.status.phase \
  --no-headers
```

```bash
# MCP Lifecycle Operator — kubernetes-sigs upstream, manages server deployments
oc get deploy -n mcp-lifecycle-operator-system \
  mcp-lifecycle-operator-controller-manager \
  --no-headers
```

> **Value:** "These aren't custom scripts. They're operators — they watch, reconcile, and self-heal. You declare what you want, and they make it happen."

---

## Phase 2: Deploy an MCP Server

> **What to say:** "You have an MCP server. It runs locally, maybe in Docker. Here's what it looks like to deploy it on OpenShift AI. You write one YAML — an MCPServer custom resource — and the operator does the rest."

```bash
# The MCPServer CR — this is ALL you write
oc get mcpserver -n mempalace -o wide
```

> **Point out:** `READY=True`, `ACCEPTED=True`, the image reference, the auto-generated service address.

```bash
# What the operator created from that one CR
oc get pods -n mempalace -o wide
```

```bash
# The image — UBI 9 base, pushed to your registry
oc get mcpserver mempalace -n mempalace \
  -o jsonpath='{.spec.source.containerImage.ref}' && echo ''
```

> **Value:** "The operator pulled the image, created the Deployment, configured health probes, and — this is the key part — performed the MCP protocol handshake. It connected to your server, ran `initialize`, and discovered every tool your server exposes. No manual registration."

```bash
# Prove the handshake works — call initialize directly on the pod
oc exec -n mempalace deploy/mempalace -- python3 -c '
import urllib.request, json
req = urllib.request.Request("http://localhost:8000/mcp",
    data=json.dumps({"jsonrpc":"2.0","id":1,"method":"initialize",
    "params":{"protocolVersion":"2025-03-26","capabilities":{},
    "clientInfo":{"name":"probe","version":"1.0"}}}).encode(),
    headers={"Content-Type":"application/json"})
r = json.loads(urllib.request.urlopen(req).read())
info = r["result"]["serverInfo"]
name, ver = info["name"], info["version"]
proto = r["result"]["protocolVersion"]
print(f"Server: {name} v{ver}")
print(f"Protocol: {proto}")
'
```

> **Expected output:** `Server: mempalace v3.3.3`, `Protocol: 2025-03-26`

---

## Phase 3: Federate via MCP Gateway

> **What to say:** "One MCP server is useful. But in production, you'll have many — financial tools, operations tools, platform tools. You need one endpoint that federates them all, with routing, access control, and tool discovery. That's the MCP Gateway."

```bash
# The Gateway — Envoy-based, managed by OpenShift AI's gateway controller
oc get gateway -n mcp-gateway-system
```

```bash
# Public hostname — this is what clients connect to
oc get mcpgatewayextension -n mcp-gateway-system \
  -o jsonpath='{.items[0].spec.publicHost}' && echo ''
```

```bash
# Three pods: the broker (protocol + registry), Envoy (routing), controller (watches CRDs)
oc get pods -n mcp-gateway-system --no-headers \
  | awk '{printf "  %-58s %s\n", $1, $3}'
```

> **Value:** "The architecture has three layers: Envoy handles HTTP, the broker handles MCP protocol parsing and tool registration, and the router handles dynamic request routing to backends. Clients see one endpoint."

```bash
# Server registration — how you tell the gateway about your MCP server
oc get mcpserverregistration -n mcp-gateway-system -o wide
```

> **Point out:** `READY=True`, `TOOLS=29`, the categories. Explain that this is all it takes to federate a server — one CR that points at an HTTPRoute.

```bash
# Broker health — continuously validates backends
oc exec -n mcp-gateway-system deploy/mcp-gateway -- \
  curl -s http://localhost:8080/status | python3 -m json.tool
```

> **What to highlight in the output:**
> - `"ready": true` — the backend passed its last health check
> - `"totalTools": 29` — every tool was discovered and registered
> - `"toolConflicts": 0` — no naming collisions across servers
> - `"lastValidated"` — the broker re-checks continuously, not just at startup

---

## Phase 4: End-to-End Data Flow

> **What to say:** "Now let's use it. A client connects to the gateway, discovers tools, stores data, and searches it — all through MCP protocol, all routed through the gateway to the backend."

### Step 4a: Initialize a session

```bash
GATEWAY="http://06536a44-eu-gb.lb.appdomain.cloud:8443"
HOST="mcp-gateway.apps.ocp-gb.ibm.redhataicatalyst.com"

# Initialize — the gateway returns a session JWT
curl -s -D /tmp/mcp_hdrs "${GATEWAY}/mcp" \
  -H "Content-Type: application/json" \
  -H "Host: ${HOST}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"demo-client","version":"1.0"}}}'

# Grab the session token
SESSION=$(grep -i 'mcp-session-id' /tmp/mcp_hdrs | tr -d '\r' | awk '{print $2}')
echo "Session: ${SESSION:0:30}..."

# Send initialized notification
curl -s "${GATEWAY}/mcp" \
  -H "Content-Type: application/json" \
  -H "Host: ${HOST}" \
  -H "Mcp-Session-Id: ${SESSION}" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
```

> **Value:** "The gateway issued a JWT session token. Every subsequent request uses this token. In the new MCP 2026-07-28 spec, sessions are retired entirely — each request becomes self-contained. The architecture we built is already aligned with that direction."

### Step 4b: Discover tools

```bash
# What tools are available through the gateway?
curl -s "${GATEWAY}/mcp" \
  -H "Content-Type: application/json" \
  -H "Host: ${HOST}" \
  -H "Mcp-Session-Id: ${SESSION}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"discover_tools","arguments":{}}}' \
  -o /tmp/mcp_resp.json

python3 << 'PYEOF'
import json
with open("/tmp/mcp_resp.json") as f:
    raw = f.read().strip()
if not raw:
    print("ERROR: Empty response — check that GATEWAY, HOST, and SESSION are set")
    exit(1)
for line in raw.splitlines():
    if line.startswith("data: "):
        raw = line[6:]
        break
r = json.loads(raw, strict=False)
data = json.loads(r["result"]["content"][0]["text"])
for srv in data["servers"]:
    print(f'Server: {srv["name"]}')
    print(f'Categories: {srv["categories"]}')
    print(f'Tools: {len(srv["tools"])} available')
    for t in srv["tools"][:8]:
        print(f"  - {t}")
    remaining = len(srv["tools"]) - 8
    if remaining > 0:
        print(f"  ... and {remaining} more")
PYEOF
```

> **Value:** "The client didn't need to know anything about the backend. It asked the gateway 'what can I do?' and got back 29 tools organized by server, category, and tags. In a multi-server deployment, this is how an AI agent discovers capabilities across your entire organization."

### Step 4c: Call a tool — check status

```bash
curl -s "${GATEWAY}/mcp" \
  -H "Content-Type: application/json" \
  -H "Host: ${HOST}" \
  -H "Mcp-Session-Id: ${SESSION}" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"mempalace_status","arguments":{}}}' \
  -o /tmp/mcp_resp.json

python3 << 'PYEOF'
import json
with open("/tmp/mcp_resp.json") as f:
    raw = f.read().strip()
if not raw:
    print("ERROR: Empty response — check that GATEWAY, HOST, and SESSION are set")
    exit(1)
for line in raw.splitlines():
    if line.startswith("data: "):
        raw = line[6:]
        break
r = json.loads(raw, strict=False)
s = json.loads(r["result"]["content"][0]["text"])
print(f'Palace path: {s["palace_path"]}')
print(f'Total drawers: {s["total_drawers"]}')
print(f'Wings: {s["wings"]}')
print(f'Rooms: {s["rooms"]}')
PYEOF
```

> **What happened here:** "The client called `mempalace_status` through the gateway. The gateway's router (ext_proc) recognized this as a tools/call, looked up which backend owns this tool, rewrote the request headers, and routed it directly to the MemPalace pod — bypassing the broker entirely. The response came back through the same path."

### Step 4d: Store knowledge

```bash
DEMO_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

curl -s "${GATEWAY}/mcp" \
  -H "Content-Type: application/json" \
  -H "Host: ${HOST}" \
  -H "Mcp-Session-Id: ${SESSION}" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"mempalace_add_drawer\",\"arguments\":{\"title\":\"MCP Lifecycle on OpenShift AI - ${DEMO_TS}\",\"content\":\"The MCP Lifecycle Operator deploys servers from container images and discovers tools automatically. The MCP Gateway federates multiple servers behind one endpoint.\",\"wing\":\"wing_code\",\"room\":\"openshift-ai\",\"importance\":5,\"tags\":[\"openshift\",\"mcp\",\"demo\"]}}}" \
  -o /tmp/mcp_resp.json

python3 << 'PYEOF'
import json
with open("/tmp/mcp_resp.json") as f:
    raw = f.read().strip()
if not raw:
    print("ERROR: Empty response — check that GATEWAY, HOST, and SESSION are set")
    exit(1)
for line in raw.splitlines():
    if line.startswith("data: "):
        raw = line[6:]
        break
r = json.loads(raw, strict=False)
d = json.loads(r["result"]["content"][0]["text"])
print(f'Success: {d["success"]}')
print(f'Drawer ID: {d["drawer_id"]}')
print(f'Wing: {d.get("wing", "n/a")} / Room: {d.get("room", "n/a")}')
PYEOF
```

> **Value:** "We just stored structured knowledge through the gateway, through the router, into MemPalace's ChromaDB vector database running on OpenShift. The data was embedded using an ONNX model (all-MiniLM-L6-v2) running right in the pod — no external embedding service needed."

### Step 4e: Semantic search

```bash
curl -s "${GATEWAY}/mcp" \
  -H "Content-Type: application/json" \
  -H "Host: ${HOST}" \
  -H "Mcp-Session-Id: ${SESSION}" \
  -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"mempalace_search","arguments":{"query":"How do I get MCP servers into production?","top_k":3}}}' \
  -o /tmp/mcp_resp.json

python3 << 'PYEOF'
import json
with open("/tmp/mcp_resp.json") as f:
    raw = f.read().strip()
if not raw:
    print("ERROR: Empty response — check that GATEWAY, HOST, and SESSION are set")
    exit(1)
for line in raw.splitlines():
    if line.startswith("data: "):
        raw = line[6:]
        break
r = json.loads(raw, strict=False)
s = json.loads(r["result"]["content"][0]["text"])
print(f'Query: "{s["query"]}"')
print(f'Results: {len(s["results"])}')
print()
for res in s["results"][:3]:
    sim = res["similarity"]
    text = res["text"][:140] + "..." if len(res["text"]) > 140 else res["text"]
    print(f'  {sim:.1%} — {res["wing"]}/{res["room"]}')
    print(f'  {text}')
    print()
PYEOF
```

> **Value:** "The query was natural language — 'How do I get MCP servers into production?' ChromaDB converted it to a vector embedding and found semantically similar content. This is the full round trip: client → gateway → router → backend → ChromaDB → vector search → response. All on OpenShift AI."

---

## Phase 5: How the Routing Works

> **What to say:** "Let me show you what actually happened under the hood. The gateway has a split architecture — the broker handles protocol operations, but tools/call goes directly to the backend."

```bash
# Envoy access logs show exactly where each request was routed
oc logs deploy/mcp-gateway-data-science-gateway-class \
  -n mcp-gateway-system --tail=10 2>&1 \
  | grep 'mempalace-backend' | tail -3
```

> **What to point out in the logs:**
> - `"mempalace-backend"` — this is the `:authority` header AFTER the router rewrote it. It's not a DNS name — it's a routing marker that matches the backend's HTTPRoute.
> - `"10.129.13.62:8000"` — the actual pod IP. The request went directly to the MemPalace pod.
> - `outbound|8000||mempalace.mempalace.svc.cluster.local` — Envoy resolved it through the Kubernetes service.

> **Key insight:** "The broker never sees tools/call requests. It handles initialize, tools/list, and discovery. The router (ext_proc gRPC filter) intercepts tools/call, strips the prefix, rewrites the authority header, clears Envoy's route cache, and the request goes straight to the backend. This means tool execution has the same latency as a direct call — the gateway adds routing, not overhead."

---

## Phase 6: Adding Another Server

> **What to say:** "This is one server. Here's what it takes to add a second, third, or tenth."

```bash
# Show the four resources that make up a server registration
echo "To add a new MCP server behind the gateway, you need:"
echo ""
echo "1. MCPServer CR (in the server's namespace)"
echo "   - Points to a container image"
echo "   - Operator handles deployment, probes, handshake"
echo ""
echo "2. HTTPRoute (in the gateway namespace)"  
echo "   - Unique hostname as routing marker"
echo "   - Points to the server's Service"
echo ""
echo "3. MCPServerRegistration (in the gateway namespace)"
echo "   - Categories, tags, hint"
echo "   - Points to the HTTPRoute"
echo ""
echo "4. ReferenceGrant (in the server's namespace)"
echo "   - Allows cross-namespace routing"
echo "   - RBAC boundary"
```

> **Value:** "Each server gets its own namespace, its own RBAC, its own resource quotas. The gateway federates them under one endpoint. Financial tools in one namespace, operations tools in another, platform tools in a third — each with different access controls. The gateway handles the routing."

---

## Phase 7: Where the Spec Is Going

> **What to say:** "Three weeks ago, the MCP specification released its biggest update — version 2026-07-28. Here's why what we just showed you is already aligned with where the protocol is heading."

### The big changes:

> 1. **Stateless protocol** — The spec retired the `initialize`/`initialized` handshake and the session ID header. Every request is now self-contained. The spec says: *"Any request can land on any instance behind a plain round-robin load balancer without shared storage."* Our gateway architecture already works this way — the upgrade makes it simpler.

> 2. **Header-based routing** (SEP-2243) — New required headers: `Mcp-Method: tools/call`, `Mcp-Name: mempalace_search`. This is exactly what our ext_proc router does by parsing the body today. The spec now puts routing info in HTTP headers so gateways don't need to inspect the body at all. Our upgrade path: read headers instead of parsing JSON.

> 3. **Enterprise Managed Authorization** — A formal extension for fine-grained auth. Maps directly to the Zero Trust / RBAC model in the architecture diagram.

> 4. **Industry validation** — Microsoft Foundry calls it a *"unified MCP endpoint with centralized governance, identity, and observability."* AWS Bedrock, Cloudflare, Stackwatch — all citing the same gateway federation pattern we just demonstrated.

### Our position:

> - Deployed on the current supported spec (2025-03-26)
> - Architecture already matches the 2026-07-28 direction
> - 12-month deprecation window — clear, planned upgrade path
> - The same pattern validated by major cloud providers, built on Red Hat's stack

---

## Quick Reference

### Key URLs and endpoints

| What | Where |
|------|-------|
| Cluster API | `https://api.ocp-gb.ibm.redhataicatalyst.com:6443` |
| Gateway LB | `http://06536a44-eu-gb.lb.appdomain.cloud:8443` |
| Gateway Host header | `mcp-gateway.apps.ocp-gb.ibm.redhataicatalyst.com` |
| MemPalace internal | `http://mempalace.mempalace.svc.cluster.local:8000/mcp` |
| Broker status | `curl localhost:8080/status` (from mcp-gateway pod) |

### Key namespaces

| Namespace | What's in it |
|-----------|-------------|
| `mempalace` | MCPServer, pod, service account, quay pull secret |
| `mcp-gateway-system` | Gateway, broker, Envoy, MCPServerRegistration, HTTPRoutes |
| `mcp-lifecycle-operator-system` | MCP Lifecycle Operator controller |

### Component versions

| Component | Version |
|-----------|---------|
| OpenShift | 4.21.8 |
| OpenShift AI | 3.4.2 |
| MCP Lifecycle Operator | v0.2.0 |
| MCP Gateway Operator | v0.7.1 (Tech Preview) |
| MemPalace | v3.3.3, UBI 9, ChromaDB 1.5.9 |
| MCP Protocol | 2025-03-26 (deployed), 2026-07-28 (upgrade path) |

### The customer question and the answer

> **"We have MCP servers. How do we get them into production?"**
>
> 1. Package in a UBI 9 container with streamable HTTP transport
> 2. Push to your registry (quay.io, internal)
> 3. Write one MCPServer CR — the operator deploys it, probes it, discovers tools
> 4. Write one MCPServerRegistration — the gateway federates it
> 5. Clients connect to one endpoint, discover tools across all servers, call any tool
>
> No custom routing code. No manual service mesh config. No tool registration scripts. Declare what you want, operators make it happen.
