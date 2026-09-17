# Saudi Aramco MCP + MaaS Demo Story

This is the presenter guide for the Act-based CLI and the hosted UI. The point
is to tell one coherent platform story in two views:

- **CLI:** proves each control-plane transition and lets the presenter stop at
  every boundary.
- **UI:** makes the live request path legible for the audience and links the
  same run to MLflow.

## Start the Demo

From the repository root:

```bash
oc login --token=<fresh-token> --server=https://api.ocp-gb.ibm.redhataicatalyst.com:6443
STEP_MODE=1 ./demos/mcp-gateway-lifecycle-demo.sh
```

Use `SEED_DEMO=1` when the audience needs a fresh MemPalace memory set:

```bash
STEP_MODE=1 SEED_DEMO=1 ./demos/mcp-gateway-lifecycle-demo.sh
```

For a rehearsal without pauses, use `SKIP_WAIT=1`. The CLI holds credentials
in memory and does not print token values.

## The Customer Narrative

**Opening:** “Saudi Aramco has two different kinds of AI capability: knowledge
that belongs to the organization, and live operational state in the platform.
We will put both behind one governed MCP endpoint, let a MaaS model use them,
and measure the complete round trip.”

| Act | CLI proof | Parallel UI moment | Message to emphasize |
|---|---|---|---|
| 1. Platform | OpenShift, MCP operators, MaaS, MLflow | Keep UI on its landing page | OpenShift AI is the control plane for the complete stack. |
| 2. Tool plane | MemPalace and read-only OpenShift MCP workloads | No click yet | The servers are separate trust domains with different responsibilities. |
| 3. Federation | Two `MCPServerRegistration` objects and 46 tools | Later, point out one gateway connection | The client sees one MCP endpoint, not backend sprawl. |
| 4. Security | No token → 401; valid RHBK token → initialized gateway session | UI’s first pipeline row is RHBK OIDC | Identity is enforced before MCP traffic reaches the gateway. |
| 5. Protocol | `tools/list`, `resources_get`, `mempalace_search` | Click Run round trip after this Act | These are live MCP calls, not simulated UI events. |
| 6. Model | `./run.sh` calls MaaS Granite with both observations | UI shows the same two backend rows | Granite combines current cluster state with institutional memory. |
| 7. Telemetry | MLflow experiment and run URL | Open the UI’s MLflow link | The result is observable, not just a response on a screen. |
| 8. UI | Dashboard flag, selector ConfigMap, hosted health | Run the same task in the browser | The UI is the approachable view of the CLI-proven path. |
| 9. Production posture | NetworkPolicy, PVC, Envoy artifacts | Keep the UI visible as context | Name the Tech Preview workaround and remaining gaps honestly. |
| 10. Close | Architecture recap | Leave UI and MLflow links on screen | One governed tool plane connects identity, tools, model, and evidence. |

## Exact Task for Both Views

Use the same task in the CLI and the UI:

```text
Summarize the current MCP gateway architecture using the live cluster and memory observations.
```

The CLI’s grounding phase calls:

1. `resources_get` on the `openshift-mcp` Deployment through the secured gateway.
2. `mempalace_search` for “OIDC gateway architecture” through the same gateway.

Granite receives both live observations and can select additional tools. The
hosted UI renders those grounding steps as **OpenShift MCP** and **MemPalace**
rows, then displays Granite’s answer and the MLflow run link.

## What to Say During the UI Handoff

“Everything we just proved in the terminal is now visible in a click-to-run
view. The first rows are identity and gateway initialization. The two rows named
OpenShift MCP and MemPalace are the two live backend calls, not two separate
applications pretending to be connected. Granite receives those observations
through MaaS and produces the answer. The MLflow link lets us inspect the same
request as a measured run: tools discovered, tool calls, per-hop durations, and
success status.”

Hosted surfaces:

- UI: `https://maas-mcp-demo-maas-mcp-demo.apps.ocp-gb.ibm.redhataicatalyst.com`
- AI Hub: `https://rh-ai.apps.ocp-gb.ibm.redhataicatalyst.com/`
- MLflow: `https://mlflow-praxis-verified.apps.ocp-gb.ibm.redhataicatalyst.com/#/experiments/2`

## Production-Honest Close

The demo should end with the boundary between “live today” and “next step”:

- Live OIDC enforcement uses the Envoy `jwt_authn` edge and returns 401 for an
  unauthenticated request.
- The native Kuadrant `AuthPolicy` is the GA-target design, but the current Tech
  Preview wasm-shim path fails closed on this user-created gateway.
- NetworkPolicy prevents direct backend bypass.
- The PVC-backed StatefulSet is the durability path while the lifecycle CRD’s
  storage source remains limited.
- The OpenShift MCP server is read-only and uses its own service-account token;
  it does not treat the gateway’s RHBK token as a Kubernetes credential.

The closing sentence is: **“The model is not the platform story by itself. The
platform story is identity, federation, live tool execution, model serving, and
evidence of what happened—all connected end to end.”**

## Presenter Checklist

Before the call:

- `oc whoami` works and the token is fresh.
- Both registrations report `READY=True`.
- The gateway reports 46 tools.
- The hosted UI `/healthz` endpoint returns 200.
- MLflow is reachable and the `aramco-mcp-maas-roundtrip` experiment exists.

During the call:

- Keep `STEP_MODE=1` enabled.
- Do not skip Act 4; the 401/valid-token contrast explains the trust boundary.
- Do not skip Act 5; it proves the UI’s two backend rows are real MCP calls.
- Do not describe MemPalace as a native AI Hub catalog item; it is exposed via
  the secured gateway selector. The native catalog entry is Red Hat OpenShift
  MCP.
