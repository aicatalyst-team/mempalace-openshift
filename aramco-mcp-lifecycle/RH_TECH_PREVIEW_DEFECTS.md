# Red Hat Connectivity Link (Tech Preview) — MCP Gateway OIDC Defect Report

**Reporter:** Gerald Trotman (Red Hat)
**Date:** 2026-09-13
**Component:** Red Hat Connectivity Link 1.4 (Tech Preview) — MCP Gateway + Kuadrant/Authorino
**Severity:** High (OIDC/AuthPolicy enforcement is unusable on user-created gateways)
**Status:** Two defects, both reproduced and root-caused with a working workaround in place

---

## Environment

| Component | Version / Image |
|-----------|-----------------|
| OpenShift | 4.21.8 (Kubernetes v1.34.5) |
| OpenShift AI (rhods-operator) | 3.5.0 |
| Red Hat Connectivity Link (rhcl-operator) | v1.4.2 (Succeeded; **v1.4.3 upgrade shows `Failed`**) |
| MCP Gateway operator | mcp-gateway **v0.7.1** — `registry.redhat.io/rhcl-tech-preview/mcp-gateway-rhel9` |
| Authorino operator / Authorino | v1.4.2 — `registry.redhat.io/rhcl-1/authorino-rhel9` |
| Limitador | v1.4.1/1.4.2 |
| MCP Lifecycle operator | v0.2.0 — `registry.k8s.io/mcp-lifecycle-operator:v0.2.0` |
| RHBK (Keycloak) operator | v26.6.6-opr.1 |
| Service Mesh | servicemeshoperator3 v3.4.1 (Istio); MCP gateway data plane = `istio-proxyv2-rhel9` |

> Environment note: `authorino-operator.v1.4.3`, `rhcl-operator.v1.4.3`, `limitador-operator.v1.4.2`, and `dns-operator.v1.4.2` all show CSV phase `Failed` (upgrades did not complete); the cluster is running the v1.4.2 line. This partially-failed upgrade state may be relevant.

---

## Defect 1 — Authorino ships with a non-existent outbound CA trust bundle

### Summary
An `AuthPolicy` using JWT/OIDC (`authentication.jwt.issuerUrl`) fails because Authorino cannot complete OIDC discovery — it trusts **no** outbound CAs, so *every* HTTPS issuer (including public CAs) fails with `x509: certificate signed by unknown authority`. Auth then fails **closed** (HTTP 503 for all traffic on the gateway).

### Impact
No external OIDC issuer works out of the box. Any `AuthPolicy` with a `jwt.issuerUrl` renders the target gateway fully unavailable (503).

### Root cause
The Authorino deployment sets:
```
SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt
REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt
```
…but **no volume mounts that path**. The only mounted volume is `tls-cert` (`authorino-server-cert`) at `/etc/ssl/certs/tls.crt`. With `SSL_CERT_FILE` pointing at a missing file, Go's TLS stack loads an empty root pool → trusts nothing outbound.

### Evidence
```
# File is absent inside the Authorino pod:
$ oc exec -n kuadrant-system deploy/authorino -- ls /etc/ssl/certs/openshift-service-ca/
ls: cannot access '/etc/ssl/certs/openshift-service-ca/': No such file or directory

# In-pod HTTPS to the OIDC issuer fails (curl exit 77 = cert error):
in-pod HTTPS to issuer -> 000 (exit 77)

# Authorino log:
"failed to discovery openid connect configuration",
 "issuerUrl":"https://<keycloak>/realms/mcp",
 "error":"...x509: certificate signed by unknown authority"
```

### Workaround (applied)
Patch the `Authorino` CR to mount the platform-standard trusted CA bundle at the referenced path:
```yaml
spec:
  volumes:
    items:
    - name: trusted-ca
      mountPath: /etc/ssl/certs/openshift-service-ca
      configMaps: [ odh-trusted-ca-bundle ]
      items:
      - key: ca-bundle.crt
        path: service-ca-bundle.crt
```
After this, the in-pod probe returns 200 and OIDC discovery succeeds.

### Suggested fix
The Authorino/RHCL operator should mount a valid CA bundle (the ODH/cluster trusted bundle, or the service-CA bundle it references) at the `SSL_CERT_FILE` path by default. As shipped, `SSL_CERT_FILE` references a path that is never populated.

---

## Defect 2 — Kuadrant AuthPolicy enforcement fails on any user-created gateway (wasm-shim → Authorino)

### Summary
With Defect 1 worked around (Authorino trust healthy, OIDC discovery OK, `AuthPolicy` reports `Enforced=True`), enforcing an `AuthPolicy` on a **user-created** gateway returns **HTTP 500 for every request** (token or not). The Envoy data plane logs:
```
envoy wasm kuadrant_wasm_shim: gRPC status code is not OK
"POST /mcp HTTP/1.1" 500 ...
```
The identical Authorino returns clean `401`/`200` for the **installer-provisioned** MaaS gateway (`maas-default-gateway`, `openshift-default` class). It fails on:
- the **MCP gateway** (`data-science-gateway-class`), and
- a **freshly-created `openshift-default`-class gateway** (ruling out gateway class and the MCP `ext_proc` filter as the cause).

### Impact
OIDC/AuthPolicy cannot be enforced on the MCP gateway — or any gateway created after install. Only the installer-wired MaaS gateway works.

### Root cause (two contributing layers)
1. **Missing ext_authz cluster.** The Kuadrant-generated `kuadrant-auth-<gw>` EnvoyFilter uses `applyTo: CLUSTER`, `operation: ADD`, `match.cluster.service: authorino-authorino-authorization…`. On the MaaS gateway the Envoy has `outbound|50051||authorino-authorino-authorization…` (istio mesh outbound). On user-created gateways the authorino ext_authz cluster is **not present** in the Envoy config (`/clusters` shows no `kuadrant-auth-service` / authorino:50051), so the wasm-shim's gRPC target does not exist.
2. **gRPC Check never reaches Authorino even once the cluster exists.** After manually programming a `kuadrant-auth-service` STRICT_DNS cluster to `authorino…:50051` (which then shows `cx_connect_fail=0`, `health_flags::healthy`), requests **still** return 500. Authorino at debug log level shows **zero request-time entries** for these calls (only AuthConfig reconciles) — i.e. the wasm-shim's gRPC `Check` TCP-connects but never lands in Authorino's application layer.

### Isolation proof
| Gateway | Class | Result (same Authorino, same issuer) |
|---------|-------|--------------------------------------|
| `maas-default-gateway` (installer) | openshift-default | clean **401** unauth |
| `mcp-gateway` | data-science-gateway-class | **500** (`wasm_shim gRPC not OK`) |
| freshly-created gateway | openshift-default | **500** (even with auth cluster added + no ext_proc) |

### Workaround (in place)
Edge OIDC enforcement independent of the Kuadrant wasm-shim — a standalone Envoy `jwt_authn` filter validating RHBK JWTs against the realm JWKS, forwarding valid requests to the MCP gateway. Verified live: `401` no/invalid token, `200` valid token → real federation. Manifest: `hardening/oidc-edge-envoy-jwt.yaml`.

### Suggested fix
Kuadrant/RHCL must program the ext_authz cluster and wasm configuration correctly for gateways created **after** install, across all istiod control planes and gateway classes (not only the installer-provisioned MaaS gateway). Additionally, investigate why the wasm-shim → Authorino gRPC `Check` does not reach Authorino's application layer on non-MaaS gateways even when the cluster is healthy.

---

## Reproduction (both defects)

1. Deploy an OIDC issuer (RHBK realm) with a service-account client.
2. Create a gateway (MCP `data-science-gateway-class`, or any new `openshift-default` gateway) with an HTTPRoute.
3. Apply a Kuadrant `AuthPolicy` targeting the gateway with `authentication.jwt.issuerUrl`.
4. Observe Defect 1 (503, Authorino x509 error). Apply the CA workaround.
5. Observe Defect 2 (500, `kuadrant_wasm_shim: gRPC status code is not OK`), while the installer MaaS gateway returns clean 401/200 with the same Authorino.

## Safety observation (positive)
Both failure modes fail **closed** (503/500), never open — no authentication bypass was ever possible during any failure state.
