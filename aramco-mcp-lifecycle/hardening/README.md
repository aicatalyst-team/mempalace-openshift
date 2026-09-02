# MCP stack hardening — reusable pattern artifacts

Server-agnostic fixes for the three gaps in [`../diagrams/mcp-stack-gaps.png`](../diagrams/mcp-stack-gaps.png).
These live in the pattern layer (not MemPalace) because all three are properties
of the **Red Hat MCP stack**, not of any one MCP server.

## Whose onus is it, really?

The gaps are stack-*layer* concerns, but that does **not** mean the platform is
deficient. For each gap the underlying capability already exists — the question
is only who wires it up.

| Gap | Does OpenShift AI / RHCL lack the capability? | Real owner | Nature |
|-----|-----------------------------------------------|------------|--------|
| **1 — OIDC auth** | **No.** Red Hat Connectivity Link ships `AuthPolicy` → Authorino; it is the documented auth mechanism for the MCP gateway. | **Us** — apply the `AuthPolicy`. | Configuration gap |
| **2 — backend bypass** | **No.** `NetworkPolicy` is core OpenShift; RHCL rides Istio, so mesh mTLS + `AuthorizationPolicy` are also available. | **Us** — apply a NetworkPolicy (or mesh mTLS). Plus an *optional* operator-UX ask (below). | Architecture completeness / operator UX |
| **3 — PVC storage** | **No.** OpenShift has fully mature PVC/CSI storage. | **Upstream operator** — the `MCPServer` CRD just doesn't expose a PVC source. | Operator API maturity (file an FR) |

**Takeaway:** none of the three is "OpenShift AI must natively build something new."
Two are configuration (1, 2) and one is an upstream operator API gap (3).

### Why Gap 2 is not a gateway bug
The MCP gateway is an **L7** component: it authenticates and routes requests that
pass *through* it. It has no authority over **L3/L4** reachability between pods —
by design, and identically for every L7 gateway (Istio ingress, NGINX, Kong…).
A gateway secures the front door; it does not wall off the building. Any client
with a route to the backend `Service` can talk to it directly, and the gateway
never sees that traffic. The complementary control is network segmentation:

```yaml
# Gap 2 fix (illustrative) — default-deny to the backend except from the gateway ns
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mempalace-allow-gateway-only
  namespace: mempalace
spec:
  podSelector: { matchLabels: { app: mempalace } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: mcp-gateway-system }
      ports:
        - { protocol: TCP, port: 8000 }
```

**Legitimate product/roadmap ask:** should the MCP Gateway operator auto-scaffold
a NetworkPolicy like this when an `MCPServerRegistration` is created, so the
secure posture is the default rather than an opt-in the operator silently omits?
That — not "build NetworkPolicy" — is the real "native support" request for Gap 2.

## Gap 1 — implemented here

[`authpolicy-oidc.yaml`](authpolicy-oidc.yaml) — OIDC/JWT enforcement on the
gateway `mcp` listener. Schema verified 2026-09-02 against the sources below.

Apply and verify:

```bash
oc apply -f authpolicy-oidc.yaml
oc get authpolicy mcp-auth-policy -n mcp-gateway-system -o yaml   # Enforced=True
# unauthenticated request should now 401 with a WWW-Authenticate challenge:
curl -si -X POST http://<gateway>:8443/mcp -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | head -1
```

Caveats to state to the customer:
- **Tech Preview** — the MCP gateway in RHCL 1.4 has no production SLA.
- **Audience/roles are authorization rules**, not a `jwt.aud` field (see the YAML comments).
- **`iss` / host reachability** is the most common failure: `issuerUrl` must be
  reachable in-cluster and must match the `iss` claim in issued tokens.

## Official documentation cross-reference

### Lifecycle management (MCP Lifecycle Operator)
- Red Hat — *Manage MCP servers with the MCP Lifecycle Operator*: https://www.redhat.com/en/blog/manage-mcp-servers-red-hat-openshift-mcp-lifecycle-operator
- Upstream (`MCPServer` CRD, storage source enum — no PVC through v0.3.0): https://github.com/kubernetes-sigs/mcp-lifecycle-operator

### Gateway + authentication
- RHCL 1.4 — MCP gateway introduction (Tech Preview; Istio + AuthPolicy): https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.4/html/mcp_gateway/mcp-gateway-introduction
- RHCL 1.4 — Registering MCP servers & creating policies (OIDC / Vault): https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.4/html/registering_mcp_servers_and_creating_policies/mcp-gateway-vault
- Red Hat Developer — Advanced authN/authZ for MCP Gateway (token exchange, tool filtering, `audience` as authz): https://developers.redhat.com/articles/2025/12/12/advanced-authentication-authorization-mcp-gateway
- Kuadrant mcp-gateway — authentication guide (the `spec.defaults` + `.well-known` pattern used here): https://github.com/Kuadrant/mcp-gateway/blob/main/docs/guides/authentication.md
- Kuadrant mcp-gateway — authorization guide (tool-level CEL, `x-mcp-*` headers): https://github.com/Kuadrant/mcp-gateway/blob/main/docs/guides/authorization.md
- Kuadrant — AuthPolicy reference (`kuadrant.io/v1`, targetRef, defaults/overrides): https://docs.kuadrant.io/latest/kuadrant-operator/doc/reference/authpolicy/
- Authorino — OIDC/JWT user guide (`issuerUrl`, `iss` matching): https://docs.kuadrant.io/latest/authorino/docs/user-guides/oidc-jwt-authentication/
- Authorino — features (in-process JWT validation, JWKS auto-rotation, caching): https://github.com/Kuadrant/authorino/blob/main/docs/features.md
- Authorino — architecture (HA topology, sharding, request lifecycle): https://github.com/Kuadrant/authorino/blob/main/docs/architecture.md
