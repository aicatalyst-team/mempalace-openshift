# Federate MCP servers and close the loop with model serving on OpenShift AI

*From one MCP server to a secured, model-driven tool platform — the full Red Hat OpenShift AI stack, end to end.*

In two earlier articles we deployed the MemPalace MCP server on Red Hat OpenShift AI, then federated it behind the MCP Gateway so agents could discover and route to its tools through a single endpoint. That got us a working tool plane. But a working tool plane is not a production platform.

Three questions decide whether an enterprise can actually run this: How is access secured? Can the gateway be bypassed? Does the data survive a restart? And one question decides whether it is *useful*: can a model actually reason over these tools and complete a task end to end?

This article answers all four. We harden the deployment across three stack-level gaps, add live OIDC authentication to the MCP gateway, and close the loop by having a MaaS-hosted large language model drive the MCP tools in a live round trip — the entire OpenShift AI stack working as one system.

## Who should read this

- Platform engineers operationalizing MCP and model serving on Red Hat OpenShift AI
- Site reliability and security engineers responsible for Zero Trust access to AI tooling
- AI/ML engineers building agentic workflows that combine a served LLM with MCP tools
- Developers and architects bringing custom MCP servers into the OpenShift AI platform catalog

## What you'll learn

- How to identify and close the three production gaps that are properties of the MCP *stack*, not any single server: authentication, network bypass, and durable storage
- How to enforce OIDC on the MCP gateway with Red Hat build of Keycloak (RHBK) — including a live, honest path when a Tech Preview component is not ready
- How to connect a MaaS-served model (LiteLLM/vLLM) to the MCP gateway so the model reasons over federated tools and returns a grounded answer
- How to reason about what belongs to the platform versus the workload, so the hardening you do generalizes to every future MCP server

## Platform-native discovery: registering MCP servers in the UI

Before diving into the three gaps, a quick note on visibility. The MCP Lifecycle Operator and the Kuadrant MCP Gateway live on the cluster, but are they discoverable from the platform's UI? Yes — OpenShift AI provides a **dual-path registration system** for custom MCP servers:

1. **Kuadrant MCPServerRegistration CRD** — registers the server for *federation* (tool discovery, routing, authorization). This is what the gateway consumes.
2. **gen-ai-aa-mcp-servers ConfigMap** — registers the server for *UI visibility* (dashboard "AI hub", catalog browsing, human operators). This is what the platform's UI consumes.

To make a custom MCP server visible in the OpenShift AI dashboard, create the ConfigMap in the `redhat-ods-applications` namespace with a `servers.json` key containing metadata (name, description, category, tags, icon, documentation URL). The platform-native integration point is **ConfigMap-based**: no custom CRDs, no webhooks — just a JSON document that the gen-ai-ui component reads at startup and on ConfigMap updates.

For MemPalace, this looks like:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gen-ai-aa-mcp-servers
  namespace: redhat-ods-applications
data:
  servers.json: |
    [
      {
        "name": "MemPalace",
        "id": "mempalace",
        "category": ["memory", "knowledge-management"],
        "tags": ["ai-memory", "chromadb", "semantic-search"],
        ...
      }
    ]
```

Developers now see MemPalace in the AI hub; it is discoverable from the UI rather than a CLI-only construct.

## The gaps are the platform's, not the server's

A useful reframing up front: the hard problems here belong to the Red Hat MCP stack, not to MemPalace. Swap MemPalace for any MCP server and the same three gaps hold:

| Gap | Where it lives | Applies to |
|-----|----------------|------------|
| OIDC not enforced at the gateway | MCP Gateway (Kuadrant) | every federated server |
| Backend reachable directly, bypassing the gateway | any in-cluster Service | every backend |
| No durable storage in the `MCPServer` CR | MCP Lifecycle Operator CRD | every server (severity scales with statefulness) |

Only the *severity* of the storage gap is workload-dependent: MemPalace holds a ChromaDB vector store, so ephemeral storage is a five-alarm problem; a stateless tool server would not notice. The limitation is the platform's; the workload only decides how much it hurts.

## Gap 2 and 3: bypass and durability (fixed and verified)

**The gateway can be bypassed.** The MCP gateway is an L7 component — it federates tools, enforces per-tool authorization, terminates OIDC, and routes by protocol. It does not, and cannot, govern who can open a TCP connection to a backend pod. On a fresh deployment, any pod in the cluster can reach the MemPalace Service on port 8000 directly, skipping the gateway and every policy on it. The fix is a NetworkPolicy that admits traffic to the backend only from the gateway namespace — the "dumb backstop" that makes the gateway's rich L7 policy mandatory rather than optional:

```yaml
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
```

Verified live: a pod in the `default` namespace is blocked; a pod in `mcp-gateway-system` still reaches the backend. The gateway path is intact; the bypass is closed.

**Storage is ephemeral.** The MCP Lifecycle Operator's `MCPServer` custom resource supports only `ConfigMap`, `Secret`, and `EmptyDir` storage sources through v0.3.0 — there is no `PersistentVolumeClaim` option. EmptyDir is tied to the pod lifecycle, so a restart erases the data. For a memory server this is fatal. Until the operator gains a PVC source (a feature request worth filing), durable storage means deploying the server as a StatefulSet with a `volumeClaimTemplate` outside the operator — trading the operator's lifecycle management for durability. Verified live: with a PVC, a written record survives a pod delete and recreate.

## Gap 1: OIDC on the MCP gateway

This is the one an enterprise cares about most, and the one with the most nuance.

The native, GA-target design is a Kuadrant `AuthPolicy` on the gateway: it validates JWTs from your enterprise IdP (RHBK), leaves the OAuth protected-resource discovery path public, and enforces per-tool authorization using the resolved tool name — auth at the edge, before any tool call reaches a backend. That is the right production shape, and the policy is staged and ready.

On the current Tech Preview build, however, enforcing that policy on a *user-created* gateway fails: the request never gets a clean allow/deny. We root-caused it precisely — the Kuadrant wasm-shim's authorization call does not reach Authorino on gateways created after install, while the installer-provisioned gateway works. We filed it as a Tech Preview defect with full evidence. Importantly, it fails *closed* — a misconfiguration causes an outage, never a bypass.

So how do you demo real OIDC today, honestly? You enforce it at the edge with a component that does not depend on the Tech Preview path: a small Envoy `jwt_authn` filter that validates RHBK-issued JWTs against the realm's JWKS and forwards only authenticated requests to the gateway. Edge JWT validation is a mainstream production pattern in its own right, and the framing is honest: OIDC is enforced live today; the native Kuadrant `AuthPolicy` becomes a drop-in at GA once the defect is fixed — same issuer, same realm, no client changes.

Verified live, with no tricks:

```
$ curl -s -o /dev/null -w '%{http_code}\n' -X POST https://mcp-secure.apps.<cluster>/mcp   # no token
401
$ curl -s -o /dev/null -w '%{http_code}\n' -X POST https://mcp-secure.apps.<cluster>/mcp \
    -H "Authorization: Bearer $TOKEN"                                                       # valid RHBK JWT
200
```

A valid token reaches the real Kuadrant MCP gateway and its federated tools; a missing or invalid one is rejected at the edge.

## Closing the loop: a MaaS model driving MCP tools

Hardening earns trust; the round trip earns interest. The point of putting tools on the cluster is for a model to *use* them. So we connect a MaaS-hosted model — Granite 3.1 8B, served through LiteLLM on OpenShift AI — to the secured MCP gateway in a single agent loop:

1. The agent obtains an OIDC token from RHBK and calls the MCP gateway through the secured edge.
2. It discovers the federated tools (`tools/list`) and offers them to the model.
3. The model chooses a tool — for example, `mempalace_search` — and the agent executes it through the gateway.
4. The tool result is fed back, and the model returns a grounded, natural-language answer.

Every hop is real: RHBK OIDC, the Envoy edge, the Kuadrant MCP gateway federating 33 tools, MemPalace's ChromaDB semantic search, and Granite served through MaaS. Asked to explain how OIDC is enforced on the gateway, the model searched the memory palace and answered from the retrieved content — model reasoning grounded in live tool data, secured end to end.

Because this vLLM deployment was not started with a native tool parser, the agent drives tool selection with structured JSON prompting (a model-agnostic ReAct pattern) rather than the OpenAI tool API — no change to the model server required. When the server enables native tool calling, the same loop switches to the tools API unchanged.

A containerized web UI makes it click-to-run, visualizing each hop from OIDC to answer — the full OpenShift AI stack in one screen.

## The whole stack, as one system

```
RHBK (OIDC) ─▶ Envoy jwt_authn edge ─▶ Kuadrant MCP Gateway ─▶ MemPalace (ChromaDB)
                    (401 / 200)            (federates tools)          ▲
      MaaS / LiteLLM (Granite) ── reasons, chooses a tool ───────────┘ ── grounded answer
```

- **Model serving** — MaaS/LiteLLM/vLLM (Granite)
- **Tool federation** — Kuadrant MCP Gateway
- **Tools and data** — MemPalace MCP server on the MCP Lifecycle Operator
- **Security** — RHBK OIDC, enforced at the edge today, native `AuthPolicy` at GA
- **Defense in depth** — NetworkPolicy backstop; durable storage via PVC

## What's next

- Replace the edge with a native Kuadrant `AuthPolicy` when the Tech Preview defect is fixed — no client-side changes
- Add per-tool authorization (identity-based tool filtering) and rate limiting via Kuadrant policies
- Move durable storage into the operator once a PVC source lands upstream
- Register additional MCP servers behind the same gateway — the model gains their tools automatically

The pattern is the deliverable. Deploy an MCP server, federate it, secure it, and let a served model drive it — and every future server inherits the same hardened, model-ready platform.

---

*Try it: the manifests, the OIDC edge, the round-trip agent, and the hosted demo are in the [mempalace-openshift repository](https://github.com/aicatalyst-team/mempalace-openshift) under `aramco-mcp-lifecycle/`.*

*Gerald Trotman is a Senior Specialist Solution Architect at Red Hat, focusing on AI/ML platform engineering.*
