# MaaS LLM ↔ MCP round trip — full OpenShift AI stack demo

A live, end-to-end demonstration that ties the entire Red Hat OpenShift AI stack
together in a single agent loop: a **MaaS-hosted LLM** reasons over tools served
by an **MCP gateway**, secured by **OIDC**, backed by a real **MCP server** with
semantic search.

## What it demonstrates (every hop is real)

```
  RHBK (OIDC)                 MaaS / LiteLLM (model serving)
      │  client_credentials        │  granite-31-8b-lab-v1 (vLLM)
      ▼                            ▼
  JWT ─▶ Envoy jwt_authn edge ─▶ Kuadrant MCP Gateway ─▶ MemPalace MCP server
         (401 / 200)               (federates 33 tools)    (ChromaDB semantic search)
                                          ▲                        │
                                          └──── tools/call ────────┘
   Agent (ReAct loop): LLM decides a tool → gateway executes it → LLM synthesizes
```

1. **Auth** — the agent gets an OIDC token from the dedicated RHBK `mcp` realm.
2. **Discover** — `initialize` + `tools/list` through the OIDC-secured edge → the
   Kuadrant MCP gateway returns its federated tool catalog (MemPalace's tools).
3. **Reason** — the MaaS-served **Granite** model is given the task + tool catalog
   and chooses which tool to call.
4. **Act** — the agent executes the chosen tool via the gateway (e.g.
   `mempalace_search`, semantic search over ChromaDB).
5. **Synthesize** — the tool result is fed back; Granite produces the final,
   grounded answer.

> Tool use is driven by **structured JSON prompting (ReAct)** rather than the
> OpenAI native tool API, because this vLLM deployment was not started with
> `--enable-auto-tool-choice`/`--tool-call-parser`. The pattern is model-agnostic
> and requires no change to the model server. (When the server enables native
> tool calling, the same loop can switch to `tools=[...]`.)

## Components on the cluster

| Layer | What | Where |
|-------|------|-------|
| Model serving | Granite 3.1 8B via LiteLLM (MaaS) | `litemaas` ns / `litemaas-litellm` |
| Security | RHBK realm `mcp` + Envoy `jwt_authn` edge | `keycloak` ns / `mcp-gateway-system` |
| Federation | Kuadrant MCP Gateway (Tech Preview) | `mcp-gateway-system` |
| Tools/data | MemPalace MCP server (ChromaDB) | `mempalace` ns |

## Hosted demo (click-to-run UI)

A containerized web UI runs the round trip and visualizes every hop. Deployed
live at **https://maas-mcp-demo-maas-mcp-demo.apps.ocp-gb.ibm.redhataicatalyst.com**
(namespace `maas-mcp-demo`).

Rebuild/redeploy (builds in-cluster — no local podman/registry needed):
```bash
oc login --token=<fresh> --server=https://api.ocp-gb.ibm.redhataicatalyst.com:6443
./webapp/build-and-deploy.sh
```
The image is built via an OpenShift binary build to the internal registry; the
`maas-mcp-creds` Secret is populated from cluster values at deploy time (no
secrets in git). Uses a dedicated namespace because `aramco-demo` is Kueue-gated.

## Run (CLI)

```bash
oc login --token=<fresh> --server=https://api.ocp-gb.ibm.redhataicatalyst.com:6443
./run.sh --seed                      # seed demo memories, then run the default task
./run.sh "your own question here"    # run against an arbitrary task
```

`run.sh` derives all credentials from the cluster (LiteLLM master key; `mcp`
realm client secret via the RHBK admin API) — **no secrets are stored in git**.

## Example (verified live 2026-09-13)

Task: *"Search my memory palace for how OIDC authentication is enforced on the MCP
gateway, then summarize."*

Granite chose `mempalace_search`, the gateway executed it (OIDC-checked), semantic
search returned the stored drawers, and Granite answered:

> "OIDC authentication on the MCP gateway is enforced by an Envoy jwt_authn edge
> that validates RHBK-issued JWTs against the mcp realm JWKS. Missing or invalid
> tokens result in HTTP 401, while valid tokens are passed to the Kuadrant MCP
> federation gateway…"

## Notes / next steps

- **Containerize + deploy** the agent (e.g. in `aramco-demo`) for a hosted demo
  UI instead of a local script.
- **OIDC note:** the edge (`oidc-edge-envoy-jwt.yaml`) is the live workaround for
  the TP wasm-shim defect (see `../RH_TECH_PREVIEW_DEFECTS.md`). At GA this becomes
  a native Kuadrant `AuthPolicy` on the gateway — the agent is unaffected.
- **Durability:** seed data lives in MemPalace's EmptyDir today; use the Gap 3
  StatefulSet+PVC (`../hardening/mempalace-statefulset-pvc.yaml`) for persistence.
