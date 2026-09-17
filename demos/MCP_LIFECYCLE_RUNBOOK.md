# Red Hat OpenShift AI — MCP Gateway Lifecycle Runbook

**Full-stack hardened MCP deployment: from a single federated server to a model-driven tool platform.**

This runbook walks you through deploying, federating, hardening, and connecting a model to the MemPalace MCP server on OpenShift AI — covering all three production gaps and live OIDC authentication.

## Current Presenter Flow

For the complete Saudi Aramco story, use the Act-based CLI driver and its
presenter guide:

```bash
STEP_MODE=1 ./demos/mcp-gateway-lifecycle-demo.sh
```

See [`aramco-mcp-lifecycle/SAUDI_ARAMCO_E2E_STORY.md`](../aramco-mcp-lifecycle/SAUDI_ARAMCO_E2E_STORY.md)
for the matching UI handoff, exact task, MLflow checkpoints, and the current
Tech Preview workaround language. This runbook remains the deployment and
troubleshooting reference.

## Prerequisites

- **OpenShift cluster** (api.ocp-gb.ibm.redhataicatalyst.com or equivalent)
- **Authenticated `oc` login** — fresh token needed daily
- **Git access** to aicatalyst-team/mempalace-openshift
- **MCP Lifecycle Operator v0.2.0+** and **MCP Gateway v0.7.1** installed
- **RHBK (Red Hat build of Keycloak)** available for OIDC
- **MaaS/LiteLLM** with Granite 3.1 8B model

## Phase 1: Deploy & Federate

### 1.1 Deploy MemPalace via the MCPServer CR

The MCP Lifecycle Operator manages MemPalace on a StatefulSet (operator-managed, durable). The default MCPServer CR uses EmptyDir, which is ephemeral — data does not survive a pod restart. For a memory server this is critical, so **Gap 3** must be addressed (see Phase 2).

**Deploy the base MCPServer (short-lived demo only; harden before prod):**

```bash
oc apply -f - <<'EOF'
apiVersion: mcp.x-k8s.io/v1
kind: MCPServer
metadata:
  name: mempalace
  namespace: mempalace
spec:
  image: quay.io/aicatalyst/mempalace:operator-v2
  protocol: mcp
  port: 8000
  config:
  - path: /opt/app-root/data
    permissions: ReadWrite
    source:
      type: EmptyDir
      emptyDir:
        sizeLimit: 10Gi
EOF
```

**Verify it reaches Ready:**
```bash
oc get mcpserver mempalace -n mempalace -w
# READY=True, ACCEPTED=True
```

### 1.2 Register with the MCP Gateway

The Kuadrant MCP Gateway discovers MemPalace via a `MCPServerRegistration`. This tells the gateway where to find the server, which tools it exposes, and how to route them.

```bash
oc apply -f - <<'EOF'
apiVersion: mcp.kuadrant.io/v1
kind: MCPServerRegistration
metadata:
  name: mempalace
  namespace: mcp-gateway-system
spec:
  serverAddress: "http://mempalace.mempalace.svc.cluster.local:8000/mcp"
  tools:
  - mempalace_status
  - mempalace_search
  - mempalace_add_drawer
  - mempalace_list_drawers
  # ... (full tool list in aramco-mcp-lifecycle/hardening/README.md)
EOF
```

**Verify federation:**
```bash
oc get mcpserverregistration mempalace -n mcp-gateway-system
# READY=True, TOOLS=29+ (all MemPalace tools)
oc get httproute -n mcp-gateway-system
# mcp-gateway-route should list mempalace as a parent ref
```

You now have a federated gateway with MemPalace's tools. But it's open to the network, unencrypted, and not yet hardened for production. Phase 2 closes the three critical gaps.

### 1.3 Add the catalog-supported OpenShift MCP server

OpenShift AI's native MCP catalog already includes the Red Hat OpenShift MCP
server. Deploy the read-only catalog image as a second backend and register it
with the same gateway:

```bash
oc apply -f aramco-mcp-lifecycle/hardening/openshift-mcp-server.yaml
oc get mcpserverregistration mempalace openshift-mcp -n mcp-gateway-system
# Both registrations should report READY=True.
# Expected live tool counts: MemPalace=29, OpenShift MCP=13.
```

The backend uses the `view` ClusterRole and sets
`cluster_auth_mode = "kubeconfig"`. This matters because the gateway forwards
the RHBK bearer token; the OpenShift MCP server must use its own pod
service-account token for Kubernetes API calls.

### 1.4 Register with the OpenShift AI UI Catalog

OpenShift AI 3.5 has two separate UI registration paths. The Gen AI chat MCP selector reads `gen-ai-aa-mcp-servers`; the native **AI Hub → MCP servers** tab reads the model-catalog source in `rhoai-model-registries`. Apply the prepared manifests:

```bash
oc apply -f aramco-mcp-lifecycle/hardening/ui-catalog-registration.yaml
oc apply -f aramco-mcp-lifecycle/hardening/native-mcp-catalog-registration.yaml
oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
  --type=merge -p '{"spec":{"dashboardConfig":{"mcpCatalog":true}}}'
```

**Verify it appears in the dashboard:**
1. Navigate to **OpenShift AI home** → **AI hub** (top menu)
2. Click **Browse, manage, and deploy models and MCP servers** → **MCP servers**
3. The native MCP servers tab should show the catalog-supported **Red Hat
   OpenShift MCP server**. The Gen AI chat MCP selector should offer the
   federated Aramco gateway, which exposes both OpenShift MCP and MemPalace
   tools through one connection.

The gateway continues to federate both backends through the MCPServerRegistration
CRDs. The ConfigMap makes the secured Aramco gateway selectable in Gen AI chat,
while the native AI Hub tab is populated by the catalog-supported OpenShift MCP
entry. These are complementary platform integration points.

## Phase 2: Harden — Close the Three Gaps

### Gap 2: Network Bypass (L3/L4 backstop)

**The problem:** Any pod in the cluster can open a TCP connection to MemPalace on port 8000, bypassing the gateway and its L7 policies.

**The fix:** A NetworkPolicy that admits traffic to the backend only from the gateway namespace.

```bash
oc apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mempalace-allow-gateway-only
  namespace: mempalace
spec:
  podSelector:
    matchLabels:
      app: mempalace
  policyTypes: [ Ingress ]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: mcp-gateway-system
    ports:
    - protocol: TCP
      port: 8000
EOF
```

**Verify:**
```bash
# From default ns (should block):
oc run probe --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi-minimal -n default \
  -- bash -c "curl -m 5 http://mempalace.mempalace.svc:8000/health || echo BLOCKED"
# Should timeout/fail

# From mcp-gateway-system (should pass):
oc run probe --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi-minimal -n mcp-gateway-system \
  -- bash -c "curl -m 5 http://mempalace.mempalace.svc:8000/health"
# Should return 200
```

### Gap 3: Ephemeral Storage → Durable PVC

**The problem:** The MCPServer CR supports only `EmptyDir`, `ConfigMap`, and `Secret`. Restarts erase data.

**The fix (stopgap):** Deploy MemPalace as a StatefulSet with a `volumeClaimTemplate` outside the operator. This trades operator lifecycle management for durability until the operator gains a PVC source.

**See:** `aramco-mcp-lifecycle/hardening/mempalace-statefulset-pvc.yaml`

**For production, apply this INSTEAD of the MCPServer CR above:**

```bash
oc apply -f aramco-mcp-lifecycle/hardening/mempalace-statefulset-pvc.yaml
oc rollout status statefulset/mempalace -n mempalace --timeout=180s
```

**Verify durability:**
```bash
# Write a marker
oc exec -n mempalace mempalace-0 -- sh -c 'echo "test" > /opt/app-root/data/marker.txt'

# Delete the pod
oc delete pod mempalace-0 -n mempalace

# Wait for restart and check
oc wait pod mempalace-0 -n mempalace --for=condition=Ready --timeout=60s
oc exec -n mempalace mempalace-0 -- cat /opt/app-root/data/marker.txt
# Should print "test" — data survived
```

**Trade-off:** You lose the operator's automatic handshake and lifecycle management. You gain a durable data store.

### Gap 1: OIDC Authentication (Live via Envoy edge)

**The problem:** The native, GA-target design is a Kuadrant `AuthPolicy` on the gateway. On the current Tech Preview build, enforcing it fails — the wasm-shim's gRPC call does not reach Authorino on user-created gateways. It fails *closed* (503), never open, so there's no bypass — just an outage.

**The production-honest workaround:** Enforce OIDC at the edge with an Envoy `jwt_authn` filter that validates Red Hat build of Keycloak (RHBK) tokens. This is itself a mainstream production pattern and unblocks the full-stack demo until the Tech Preview defect is fixed. **When GA releases, this edge is replaced by a native Kuadrant `AuthPolicy` — no client changes.**

#### Step 1: Create an OIDC realm on RHBK

```bash
# RHBK is already running on the cluster; create a dedicated mcp realm
oc apply -f - <<'EOF'
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: mcp-realm
  namespace: keycloak
spec:
  keycloakCRName: <your-keycloak-instance>  # e.g., gpuaas-keycloak
  realm:
    realm: mcp
    enabled: true
    clients:
    - clientId: mcp-gateway-client
      enabled: true
      protocol: openid-connect
      publicClient: false
      serviceAccountsEnabled: true
      standardFlowEnabled: false
      secret: <generate-a-random-secret>
      protocolMappers:
      - name: mcp-audience
        protocol: openid-connect
        protocolMapper: oidc-audience-mapper
        config:
          "included.custom.audience": "mcp-gateway"
          "access.token.claim": "true"
          "id.token.claim": "false"
EOF
```

**Save the client secret securely** — you'll need it to configure the edge.

#### Step 2: Deploy the Envoy jwt_authn edge

The edge is a minimal Envoy sidecar that validates JWTs before forwarding to the gateway.

```bash
oc apply -f aramco-mcp-lifecycle/hardening/oidc-edge-envoy-jwt.yaml
oc rollout status deploy/envoy-edge -n mcp-gateway-system --timeout=180s
```

#### Step 3: Verify OIDC enforcement

Get a token from your mcp realm:
```bash
KC="https://mcp-keycloak.apps.ocp-gb.ibm.redhataicatalyst.com/realms/mcp"
TOKEN=$(curl -s -X POST "$KC/protocol/openid-connect/token" \
  -d grant_type=client_credentials \
  -d client_id=mcp-gateway-client \
  -d "client_secret=<your-secret>" | jq -r .access_token)
```

Test the secured endpoint:
```bash
FRONT="mcp-secure.apps.ocp-gb.ibm.redhataicatalyst.com"

# No token → 401
curl -s -o /dev/null -w '%{http_code}\n' -X POST "https://${FRONT}/mcp" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
# → 401

# With valid token → 200
curl -s -o /dev/null -w '%{http_code}\n' -X POST "https://${FRONT}/mcp" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
# → 200 (and you reach the real Kuadrant MCP gateway)
```

**The edge is now live.** Unauthenticated requests get 401; valid tokens pass through to the gateway.

## Phase 3: Connect the Model (MaaS round-trip)

The entire point: let a served model reason over the MCP tools and return grounded answers.

### 3.1 Run the CLI agent

```bash
cd aramco-mcp-lifecycle/maas-mcp-roundtrip
./run.sh --seed  # Seeds MemPalace with demo memories, then runs the default task
./run.sh "Your custom question here"
```

The agent will:
1. Get an OIDC token from your mcp realm (via client_credentials)
2. Call `initialize` + `tools/list` through the secured edge
3. Pass the federated tools to MaaS Granite
4. The agent performs read-only grounding calls to OpenShift MCP and MemPalace
5. Granite synthesizes from both live results and may choose additional tools
6. MLflow records each hop and duration

**Example output:**
```
[AUTH] requesting RHBK OIDC token...
[AUTH] got JWT (1345 chars)
[MCP] initialize via OIDC-secured edge…
[MCP] gateway: Kuadrant MCP Gateway (session=...)
[MCP] discovered 46 federated tools
[TASK] Search my memory palace for OIDC enforcement...
[LLM] turn 1: asking MaaS Granite to decide…
[LLM] chose tool: mempalace_search({"query": "OIDC authentication"})
[MCP] executing mempalace_search through the OIDC-secured gateway…
[MCP] observation: {...retrieved drawers...}
[LLM] turn 2: asking MaaS Granite to decide…

[MCP] grounding probe: resources_get (OpenShift MCP) through the OIDC-secured gateway…
[MCP] grounding probe: mempalace_search (MemPalace) through the OIDC-secured gateway…

=== FINAL ANSWER (MaaS Granite, grounded in MCP tools) ===
OIDC authentication on the MCP gateway is enforced by an Envoy jwt_authn edge...
```

### 3.2 Run the hosted web UI demo

A containerized FastAPI app visualizes each hop from OIDC to answer.

```bash
# Demo is already deployed at:
# https://maas-mcp-demo-maas-mcp-demo.apps.ocp-gb.ibm.redhataicatalyst.com

# To rebuild/redeploy:
cd aramco-mcp-lifecycle/maas-mcp-roundtrip/webapp
./build-and-deploy.sh
```

The UI shows the full pipeline in real time:
1. **RHBK OIDC** — token issued
2. **Envoy edge** — JWT validated → 200
3. **MCP Gateway** — 46 federated tools discovered
4. **OpenShift MCP + MemPalace** — both backends called
5. **MaaS Granite** — synthesized the grounded answer
6. **MLflow** — run link exposes timings, tool calls, and status

---

## Cluster Endpoints (api.ocp-gb)

| Component | Endpoint | Notes |
|-----------|----------|-------|
| **Open MCP demo** | `mcp-gateway.apps.ocp-gb...` | Unauth, 46 federated tools |
| **Secured MCP** | `https://mcp-secure.apps.ocp-gb...` | OIDC-enforced edge, 401/200 |
| **MaaS LLM** | `litemaas-litellm-litemaas.apps...` | Granite via LiteLLM |
| **RHBK** | `mcp-keycloak.apps.ocp-gb...` | realm `mcp`, client `mcp-gateway-client` |
| **Hosted demo UI** | `maas-mcp-demo-maas-mcp-demo.apps...` | FastAPI, click-to-run |
| **MLflow** | `https://mlflow-praxis-verified.apps...` | `aramco-mcp-maas-roundtrip` experiment |

## Troubleshooting

**Pod can't reach backend after NetworkPolicy:**
- The NetworkPolicy is deny-by-default. Ensure the caller is in `mcp-gateway-system` namespace or add an explicit ingress rule.

**OIDC token invalid:**
- Token TTL is 1 hour by default. Regenerate if expired.
- Confirm `client_id` and `client_secret` match the realm's `mcp-gateway-client`.

**Granite returns empty answer:**
- Check the tool list is populated (46 federated tools).
- Ensure MemPalace has been seeded with data (`./run.sh --seed`).

**Demo UI 500 error:**
- Check the pod logs: `oc logs -n maas-mcp-demo deploy/maas-mcp-demo`
- Confirm creds Secret is in place: `oc get secret maas-mcp-creds -n maas-mcp-demo`

---

## What's Next

- **Per-tool authorization** — Kuadrant `AuthPolicy` with tool-level RBAC (identity-based filtering)
- **Rate limiting** — Kuadrant `RateLimitPolicy` per client/tool
- **Multiple backends** — The live demo now registers OpenShift MCP plus MemPalace; the model gains both tool sets automatically
- **Native `AuthPolicy`** — When the Tech Preview defect is fixed, replace the Envoy edge with a native Kuadrant `AuthPolicy` on the gateway (same issuer, same realm, no client changes)

---

**Repository:** https://github.com/aicatalyst-team/mempalace-openshift/tree/main/aramco-mcp-lifecycle  
**Blog:** See `BLOG_FULLSTACK_MCP_MAAS.md` for the full production narrative  
**Hosted demo:** https://maas-mcp-demo-maas-mcp-demo.apps.ocp-gb.ibm.redhataicatalyst.com
