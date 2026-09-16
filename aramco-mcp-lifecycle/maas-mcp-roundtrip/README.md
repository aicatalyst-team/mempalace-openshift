# MaaS LLM ↔ MCP round trip — full OpenShift AI stack demo

A live, end-to-end demonstration that ties the entire Red Hat OpenShift AI stack
together in a single agent loop: a **MaaS-hosted LLM** reasons over tools served
by an **MCP gateway**, secured by **OIDC**, backed by two real MCP servers, with
the complete round trip recorded in **MLflow**.

## What it demonstrates (every hop is real)

```
  RHBK (OIDC)                 MaaS / LiteLLM (model serving)
      │  client_credentials        │  granite-31-8b-lab-v1 (vLLM)
      ▼                            ▼
  JWT ─▶ Envoy jwt_authn edge ─▶ Kuadrant MCP Gateway ─┬▶ OpenShift MCP server
         (401 / 200)               (46 federated tools) └▶ MemPalace MCP server
                                                        (cluster + ChromaDB)
                                          ▲                         │
                                          └──── tools/call ──────────┘
                                                                    │
                                              MLflow experiment ◀───┘
   Agent (ReAct loop): LLM decides a tool → gateway executes it → LLM synthesizes
```

1. **Auth** — the agent gets an OIDC token from the dedicated RHBK `mcp` realm.
2. **Discover** — `initialize` + `tools/list` through the OIDC-secured edge → the
   Kuadrant MCP gateway returns the federated catalog (29 MemPalace tools + 13
   read-only OpenShift MCP tools).
3. **Reason** — the MaaS-served **Granite** model is given the task + tool catalog
   and chooses which tool to call.
4. **Act** — the agent executes read-only grounding probes via the gateway
   (`resources_get` against the cluster and `mempalace_search` over ChromaDB).
   Granite then reasons over both live observations and may choose additional
   tools.
5. **Observe** — each OIDC, MCP, MaaS, and tool hop is written to the live
   MLflow experiment `aramco-mcp-maas-roundtrip`.
6. **Synthesize** — the observations are fed back; Granite produces the final,
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
| Tools/data | Red Hat OpenShift MCP server, read-only | `openshift-mcp` ns |
| Telemetry | MLflow experiment and run traces | `praxis-verified` ns |

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

## Example (verified live 2026-09-16)

Task: *"Use the OpenShift MCP server to inspect the openshift-mcp deployment, then
use MemPalace to search for the OIDC gateway architecture. Summarize both results."*

The gateway returned **46 federated tools**. The agent called an OpenShift MCP tool
and `mempalace_search` through the OIDC-checked gateway before Granite synthesized
the answer; the app recorded the hop timings and result in MLflow. The hosted UI
links directly to the run:

`https://mlflow-praxis-verified.apps.ocp-gb.ibm.redhataicatalyst.com/#/experiments/2/runs/<run-id>`

The corresponding grounded answer includes:

> "OIDC authentication on the MCP gateway is enforced by an Envoy jwt_authn edge
> that validates RHBK-issued JWTs against the mcp realm JWKS. Missing or invalid
> tokens result in HTTP 401, while valid tokens are passed to the Kuadrant MCP
> federation gateway…"

## MLflow telemetry

The demo uses the MLflow REST API directly, so it has no Python MLflow dependency
and remains runnable from the CLI or the hosted FastAPI container. Defaults are:

```text
MLFLOW_TRACKING_URI=https://mlflow-praxis-verified.apps.ocp-gb.ibm.redhataicatalyst.com
MLFLOW_EXPERIMENT_NAME=aramco-mcp-maas-roundtrip
```

Every run records OIDC, MCP initialize, tools/list, each MaaS turn, each MCP tool
call, duration metrics, server labels, tool counts, and success/failure status.
Tracking failures are non-blocking and are reported in the UI as unavailable
telemetry rather than breaking the MCP/MaaS demo.

## Deploy the second MCP server

The second server is the Red Hat OpenShift MCP server already present in the
OpenShift AI native MCP catalog. The prepared manifest uses the same catalog image
(`registry.redhat.io/openshift-mcp-tech-preview/openshift-mcp-server-rhel9:0.4`),
a read-only `view` service account, and a private gateway backend route:

```bash
oc apply -f ../hardening/openshift-mcp-server.yaml
oc get mcpserverregistration mempalace openshift-mcp -n mcp-gateway-system
```

The `cluster_auth_mode = "kubeconfig"` setting is intentional: the OIDC edge
bearer token is for gateway authentication, while Kubernetes API calls use the
server pod's read-only service account.

## Notes / next steps

- **Hosted UI:** rebuild with `./webapp/build-and-deploy.sh` after source changes.
- **OIDC note:** the edge (`oidc-edge-envoy-jwt.yaml`) is the live workaround for
  the TP wasm-shim defect (see `../RH_TECH_PREVIEW_DEFECTS.md`). At GA this becomes
  a native Kuadrant `AuthPolicy` on the gateway — the agent is unaffected.
- **Durability:** seed data lives in MemPalace's EmptyDir today; use the Gap 3
  StatefulSet+PVC (`../hardening/mempalace-statefulset-pvc.yaml`) for persistence.
