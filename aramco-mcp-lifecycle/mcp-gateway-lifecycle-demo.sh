#!/usr/bin/env bash
# Saudi Aramco MCP + MaaS end-to-end presenter demo.
#
# Every Act pauses in STEP_MODE=1 so a presenter can explain the stack and
# advance deliberately. The CLI and hosted UI use the same live endpoints.
#
# Usage:
#   STEP_MODE=1 ./mcp-gateway-lifecycle-demo.sh
#   STEP_MODE=1 SEED_DEMO=1 ./mcp-gateway-lifecycle-demo.sh
#   SKIP_WAIT=1 ./mcp-gateway-lifecycle-demo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${GIT_ROOT}/demos/demo-lib.sh"

GRAY='\033[0;37m'

# Keep the shared presenter library unchanged while allowing a fast live
# rehearsal. STEP_MODE remains the interactive mode for a customer-facing run.
if [ "${SKIP_WAIT:-0}" = "1" ]; then
    demo_wait() { :; }
fi

HARDENING="${SCRIPT_DIR}/hardening"
ROUNDTRIP="${SCRIPT_DIR}/maas-mcp-roundtrip"
CLUSTER_API="${CLUSTER_API:-https://api.ocp-gb.ibm.redhataicatalyst.com:6443}"
KC_REALM="${KC_REALM:-https://mcp-keycloak.apps.ocp-gb.ibm.redhataicatalyst.com/realms/mcp}"
SECURE_MCP_URL="${SECURE_MCP_URL:-https://mcp-secure.apps.ocp-gb.ibm.redhataicatalyst.com/mcp}"
MAAS_URL="${MAAS_URL:-https://litemaas-litellm-litemaas.apps.ocp-gb.ibm.redhataicatalyst.com}"
MLFLOW_URL="${MLFLOW_URL:-https://mlflow-praxis-verified.apps.ocp-gb.ibm.redhataicatalyst.com}"
UI_URL="${UI_URL:-https://maas-mcp-demo-maas-mcp-demo.apps.ocp-gb.ibm.redhataicatalyst.com}"
AI_HUB_URL="${AI_HUB_URL:-https://rh-ai.apps.ocp-gb.ibm.redhataicatalyst.com/}"
MLFLOW_EXPERIMENT="${MLFLOW_EXPERIMENT:-aramco-mcp-maas-roundtrip}"
DEMO_TASK="${DEMO_TASK:-Summarize the current MCP gateway architecture using the live cluster and memory observations.}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

pass() { show_result "success" "$1"; }
warn() { show_result "warning" "$1"; }
fail_demo() { show_result "error" "$1"; exit 1; }

parse_mcp() {
    python3 -c "
import sys, json
raw = sys.stdin.read().strip()
if any(line.startswith('data: ') for line in raw.splitlines()):
    raw = ''.join(line[6:] for line in raw.splitlines() if line.startswith('data: '))
obj = json.loads(raw, strict=False)
$1
"
}

get_oidc_token() {
    local admin_user admin_password admin_token client_uuid admin_url client_secret
    admin_user="$(oc get secret mcp-keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d)"
    admin_password="$(oc get secret mcp-keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d)"
    admin_url="${KC_REALM/\/realms\/mcp/\/realms\/master}"
    admin_token="$(curl -sk -X POST "${admin_url}/protocol/openid-connect/token" \
        -d grant_type=password -d client_id=admin-cli \
        -d "username=${admin_user}" -d "password=${admin_password}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')"
    client_uuid="$(curl -sk "${admin_url/\/realms\/master/\/admin\/realms\/mcp}/clients?clientId=mcp-gateway-client" \
        -H "Authorization: Bearer ${admin_token}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])')"
    client_secret="$(curl -sk -X POST "${admin_url/\/realms\/master/\/admin\/realms\/mcp}/clients/${client_uuid}/client-secret" \
        -H "Authorization: Bearer ${admin_token}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])')"
    curl -sk -X POST "${KC_REALM}/protocol/openid-connect/token" \
        -d grant_type=client_credentials -d client_id=mcp-gateway-client \
        -d "client_secret=${client_secret}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}

MCP_TOKEN=""
MCP_SESSION=""
mcp_post() {
    local payload="$1"
    local -a headers=(
        -H "Authorization: Bearer ${MCP_TOKEN}"
        -H "Content-Type: application/json"
        -H "Accept: application/json, text/event-stream"
    )
    if [ -n "${MCP_SESSION}" ]; then
        headers+=( -H "Mcp-Session-Id: ${MCP_SESSION}" )
    fi
    curl -skS "${SECURE_MCP_URL}" "${headers[@]}" -d "${payload}"
}

run_cli_agent() {
    local log_file="${TMP_DIR}/maas-mcp-agent.log"
    echo -e "${GREEN}\$ cd ${ROUNDTRIP} && ./run.sh${SEED_DEMO:+ --seed}${NC}"
    echo -e "${GRAY}# Task: ${DEMO_TASK}${NC}"
    demo_wait "${COMMAND_PAUSE}"
    if [ "${SEED_DEMO:-0}" = "1" ]; then
        (cd "${ROUNDTRIP}" && ./run.sh --seed) 2>&1 | tee "${log_file}"
    else
        (cd "${ROUNDTRIP}" && ./run.sh "${DEMO_TASK}") 2>&1 | tee "${log_file}"
    fi
    echo ""
    if grep -q "MLFLOW" "${log_file}"; then
        pass "MaaS Granite completed the live MCP round trip and emitted an MLflow run"
    else
        warn "MaaS round trip completed without a visible MLflow URL"
    fi
}

###############################################################################
# INTRO
###############################################################################
demo_intro \
    "Saudi Aramco MCP + MaaS on OpenShift AI" \
    "From declared servers to a secured, observed model round trip" \
    "AI Catalyst Platform Team"

echo -e "${CYAN}# The customer story:${NC}"
bullet "One secured MCP endpoint federates institutional memory and live cluster operations"
bullet "Granite, served through MaaS, receives live observations and produces the grounded answer"
bullet "The CLI exposes every boundary; the hosted UI visualizes the same request path"
bullet "MLflow records the round-trip timings, servers, tools, and outcome"
echo ""
demo_wait "${ACT_PAUSE}"

###############################################################################
# ACT 1: PLATFORM READINESS
###############################################################################
act "1" "The Platform — OpenShift AI as the Control Plane"
section_header "Cluster and Operators"
run_command "oc whoami" "Authenticated OpenShift identity"
run_command "oc version | sed -n '1,3p'" "OpenShift version"
run_command "oc get csv -n mcp-gateway-system | grep -i 'mcp\|gateway' | head -5" "MCP Gateway operator"
run_command "oc get deploy -n mcp-lifecycle-operator-system mcp-lifecycle-operator-controller-manager -o wide" "MCP Lifecycle operator"

section_header "MaaS and MLflow"
run_command "oc get deploy -n litemaas litemaas-litellm -o wide" "LiteLLM MaaS gateway"
run_command "oc get deploy -n praxis-verified mlflow -o wide" "MLflow tracking server"
run_command "curl -sk -o /dev/null -w 'MLflow HTTP status: %{http_code}\\n' '${MLFLOW_URL}/'" "MLflow route"
echo -e "${CYAN}# Tell the audience:${NC}"
bullet "OpenShift AI supplies the operating plane: operators, networking, MaaS, and experiment tracking."
bullet "The application plane is intentionally simple: MCP servers, one gateway, and one model loop."
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 2: TWO MCP SERVERS
###############################################################################
act "2" "The Tool Plane — Two Servers, Two Trust Domains"
section_header "MemPalace — Institutional Memory"
run_command "oc get mcpserver mempalace -n mempalace -o wide" "MemPalace MCPServer"
run_command "oc get pods -n mempalace -l app=mcp-server -o wide" "MemPalace workload"
run_command "oc get svc -n mempalace mempalace -o wide" "MemPalace service"

section_header "OpenShift MCP — Read-Only Operations"
run_command "oc get mcpserver openshift-mcp -n openshift-mcp -o wide" "OpenShift MCPServer"
run_command "oc get pods -n openshift-mcp -o wide" "OpenShift MCP workload"
run_command "oc get sa openshift-mcp-viewer -n openshift-mcp" "Read-only service account"
run_command "oc auth can-i --as=system:serviceaccount:openshift-mcp:openshift-mcp-viewer get deployments -A" "RBAC check"
echo -e "${CYAN}# Tell the audience:${NC}"
bullet "MemPalace answers questions from institutional memory stored in ChromaDB."
bullet "OpenShift MCP answers read-only questions about the live platform."
bullet "They remain isolated by namespace and RBAC; federation happens only at the gateway."
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 3: FEDERATION
###############################################################################
act "3" "Federation — One MCP Endpoint, Many Backends"
section_header "Gateway and Registrations"
run_command "oc get gateway -n mcp-gateway-system" "Gateway API entry point"
run_command "oc get httproute -n mcp-gateway-system -o wide" "Backend routing markers"
run_command "oc get mcpserverregistration mempalace openshift-mcp -n mcp-gateway-system -o wide" "Federated MCP servers"
run_command "oc get mcpserverregistration mempalace openshift-mcp -n mcp-gateway-system -o jsonpath='{range .items[*]}{.metadata.name}{\" READY=\"}{.status.conditions[?(@.type==\"Ready\")].status}{\" TOOLS=\"}{.status.discoveredTools}{\"\\n\"}{end}'" "Registration health and tool counts"
echo -e "${CYAN}# Tell the audience:${NC}"
bullet "The client does not manage two URLs or two tool catalogs."
bullet "MCPServerRegistration binds each backend route into one gateway federation."
bullet "The live gateway reports 29 MemPalace tools plus 13 OpenShift MCP tools."
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 4: SECURITY BOUNDARY
###############################################################################
act "4" "The Front Door — OIDC Before MCP"
section_header "Unauthenticated Request"
echo -e "${GREEN}\$ curl -sk -o /dev/null -w '%{http_code}\\n' -X POST ${SECURE_MCP_URL}${NC}"
demo_wait "${COMMAND_PAUSE}"
NOAUTH="$(curl -sk -o /dev/null -w '%{http_code}' -m 20 -X POST "${SECURE_MCP_URL}" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')"
echo "HTTP status without token: ${NOAUTH}"
[ "${NOAUTH}" = "401" ] && pass "Envoy jwt_authn rejects unauthenticated MCP traffic" || warn "Expected 401, received ${NOAUTH}"

section_header "Authenticated Request"
echo -e "${GRAY}# Acquiring a short-lived client-credentials token from the mcp realm...${NC}"
MCP_TOKEN="$(get_oidc_token)"
echo "OIDC token acquired in memory: ${#MCP_TOKEN} characters"
demo_wait "${COMMAND_PAUSE}"
INIT_HEADERS="${TMP_DIR}/mcp-init.headers"
INIT_BODY="${TMP_DIR}/mcp-init.body"
curl -skS -D "${INIT_HEADERS}" -o "${INIT_BODY}" "${SECURE_MCP_URL}" \
    -H "Authorization: Bearer ${MCP_TOKEN}" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"aramco-presenter","version":"1.0"}}}'
MCP_SESSION="$(awk 'tolower($1)=="mcp-session-id:" {print $2}' "${INIT_HEADERS}" | tr -d '\r' | tail -1)"
cat "${INIT_BODY}" | parse_mcp "
print('Gateway: ' + obj['result']['serverInfo']['name'])
print('Protocol: ' + obj['result']['protocolVersion'])
"
echo "Session identifier received: ${MCP_SESSION:0:24}..."
mcp_post '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' >/dev/null
pass "Valid RHBK JWT reached the Kuadrant MCP Gateway"
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 5: RAW MCP ROUND TRIP
###############################################################################
act "5" "The Protocol — Discover, Ground, Return"
section_header "Discover Federated Tools"
TOOLS_RESPONSE="$(mcp_post '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}')"
printf '%s' "${TOOLS_RESPONSE}" | parse_mcp "
tools = obj['result']['tools']
print(f'Federated tools: {len(tools)}')
for name in ['resources_get', 'mempalace_search']:
    print(('  ✓ ' if any(t['name'] == name for t in tools) else '  ✗ ') + name)
"
demo_wait "${RESULT_PAUSE}"

section_header "Grounding Call 1 — OpenShift MCP"
OPENSHIFT_RESULT="$(mcp_post '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"resources_get","arguments":{"apiVersion":"apps/v1","kind":"Deployment","name":"openshift-mcp","namespace":"openshift-mcp"}}}')"
printf '%s' "${OPENSHIFT_RESULT}" | parse_mcp "print(obj['result']['content'][0]['text'][:1200])"
pass "Live cluster state returned through the federated gateway"

section_header "Grounding Call 2 — MemPalace"
MEMORY_RESULT="$(mcp_post '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"mempalace_search","arguments":{"query":"OIDC gateway architecture","top_k":3}}}')"
printf '%s' "${MEMORY_RESULT}" | parse_mcp "
data = json.loads(obj['result']['content'][0]['text'], strict=False)
print(f\"Query: {data['query']}\")
print(f\"Semantic matches: {len(data['results'])}\")
for result in data['results'][:3]:
    print(f\"  {result.get('similarity', 0):.1%} — {result.get('wing', 'n/a')}/{result.get('room', 'n/a')}\")
    print('  ' + result['text'][:220].replace('\\n', ' ') + '...')
"
pass "Institutional memory returned through the same federated gateway"
echo -e "${CYAN}# Tell the audience:${NC}"
bullet "This is the same path the MaaS agent uses: initialize, tools/list, tools/call."
bullet "The two backend observations are live, not hard-coded into the UI."
bullet "The gateway is the common trust and routing boundary for both server types."
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 6: MAAS AGENT
###############################################################################
act "6" "The Model — MaaS Granite Reasons Over the Tool Plane"
section_header "Run the CLI Agent"
echo -e "${GRAY}# The agent repeats the secured MCP path, presents the catalog to Granite,${NC}"
echo -e "${GRAY}# grounds against both backends, and feeds the observations to the model.${NC}"
run_cli_agent
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 7: TELEMETRY
###############################################################################
act "7" "Observability — MLflow Captures the Round Trip"
section_header "Tracking Experiment"
run_command "curl -sk '${MLFLOW_URL}/api/2.0/mlflow/experiments/get-by-name?experiment_name=${MLFLOW_EXPERIMENT}'" "MLflow experiment"
LAST_RUN_URL="$(grep -o 'https://[^ ]*/#/experiments/[0-9]*/runs/[A-Za-z0-9_-]*' "${TMP_DIR}/maas-mcp-agent.log" 2>/dev/null | tail -1 || true)"
if [ -n "${LAST_RUN_URL}" ]; then
    echo -e "${GREEN}Latest CLI run:${NC} ${LAST_RUN_URL}"
else
    echo -e "${YELLOW}Open the experiment manually:${NC} ${MLFLOW_URL}/#/experiments/2"
fi
run_command "curl -sk -o /dev/null -w 'MLflow UI HTTP status: %{http_code}\\n' '${MLFLOW_URL}/'" "MLflow UI"
echo -e "${CYAN}# What the run proves:${NC}"
bullet "OIDC token acquisition and MCP session initialization"
bullet "Federated tools discovered from both servers"
bullet "OpenShift MCP and MemPalace tool-call durations"
bullet "MaaS Granite turn timings, success state, and final outcome"
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 8: PARALLEL UI STORY
###############################################################################
act "8" "The Same Story in the OpenShift AI UI"
section_header "AI Hub Discovery"
run_command "oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications -o jsonpath='{.spec.dashboardConfig.mcpCatalog}' && echo ''" "Native MCP catalog flag"
run_command "oc get cm gen-ai-aa-mcp-servers -n redhat-ods-applications -o jsonpath='{.data.mempalace}'" "Gen AI gateway selector"
echo -e "${GREEN}AI Hub:${NC} ${AI_HUB_URL}"

section_header "Hosted Round-Trip UI"
run_command "curl -sk -o /dev/null -w 'Hosted UI health: %{http_code}\\n' '${UI_URL}/healthz'" "Hosted demo health"
echo -e "${GREEN}Hosted UI:${NC} ${UI_URL}"
echo -e "${CYAN}# Presenter handoff to the UI:${NC}"
bullet "Point to the pipeline: RHBK OIDC → Envoy edge → MCP Gateway."
bullet "Click Run round trip with the same task used in Act 6."
bullet "Point out the OpenShift MCP and MemPalace rows; they are the UI form of Act 5."
bullet "Open the MLflow run link; it is the measured version of the visual trace."
bullet "The CLI explains the trust boundaries; the UI makes the live request legible."
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 9: PRODUCTION HONESTY
###############################################################################
act "9" "Production Posture — What Is Real and What Is Next"
section_header "Defense in Depth Artifacts"
run_command "grep -E 'name:|kind:|namespace:' '${HARDENING}/networkpolicy-backend-lockdown.yaml' | head -12" "Backend bypass protection"
run_command "grep -E 'kind:|volumeClaimTemplates:|storageClassName:' '${HARDENING}/mempalace-statefulset-pvc.yaml' | head -12" "Durable storage option"
run_command "grep -E 'kind:|name:|issuerUrl|jwt_authn' '${HARDENING}/oidc-edge-envoy-jwt.yaml' | head -18" "OIDC edge workaround"
echo -e "${CYAN}# Tell the audience precisely:${NC}"
bullet "The Envoy jwt_authn edge is live: no token is 401; a valid token reaches the gateway."
bullet "Native Kuadrant AuthPolicy remains the GA-target path; the current Tech Preview wasm-shim defect fails closed on this user-created gateway."
bullet "NetworkPolicy closes direct backend reachability; PVC-backed deployment closes the EmptyDir durability gap."
bullet "This is a production-shaped pattern with clearly named Tech Preview and PoC boundaries."
demo_wait "${RESULT_PAUSE}"

###############################################################################
# ACT 10: CLOSE
###############################################################################
act "10" "The Saudi Aramco Takeaway"
echo -e "${WHITE}  One request, one platform story:${NC}"
echo ""
echo -e "  ${CYAN}RHBK OIDC${NC} → ${BLUE}Envoy edge${NC} → ${MAGENTA}MCP Gateway${NC}"
echo -e "       → ${GREEN}OpenShift MCP${NC} + ${GREEN}MemPalace${NC}"
echo -e "       → ${YELLOW}MaaS Granite${NC} → ${CYAN}MLflow trace${NC} → grounded answer"
echo ""
echo -e "${WHITE}  What was demonstrated:${NC}"
bullet "OpenShift AI operators manage the servers and gateway"
bullet "Two isolated MCP backends are federated behind one endpoint"
bullet "RHBK identity is enforced before MCP protocol traffic enters the gateway"
bullet "Granite uses live platform state and institutional memory together"
bullet "The CLI makes every transition manually explainable; the UI makes the same trace demo-friendly"
bullet "MLflow captures timing and identity context for the round trip"
echo ""
echo -e "${GREEN}Hosted UI:${NC} ${UI_URL}"
echo -e "${GREEN}AI Hub:${NC} ${AI_HUB_URL}"
echo -e "${GREEN}MLflow:${NC} ${MLFLOW_URL}/#/experiments/2"
echo -e "${GREEN}Runbook:${NC} ${GIT_ROOT}/demos/MCP_LIFECYCLE_RUNBOOK.md"
echo -e "${GREEN}Story guide:${NC} ${SCRIPT_DIR}/SAUDI_ARAMCO_E2E_STORY.md"
echo ""
pass "Saudi Aramco MCP + MaaS end-to-end story complete"
