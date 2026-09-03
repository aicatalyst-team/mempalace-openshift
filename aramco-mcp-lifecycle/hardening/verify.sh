#!/usr/bin/env bash
# =============================================================================
# Hardening verification — runs the live test sequence for Gaps 1, 2, 3.
# Requires an authenticated `oc` session against the cluster where the MCP
# Gateway + MemPalace are deployed.
#
#   oc login --token=<fresh> --server=https://api.ocp-gb.ibm.redhataicatalyst.com:6443
#   ./verify.sh
#
# Configure via env vars (defaults shown):
#   GW_NS=mcp-gateway-system   BACKEND_NS=mempalace
#   GATEWAY_URL=http://<gateway-external-address>:8443
#   KEYCLOAK_HOST=... REALM=... CLIENT_ID=... CLIENT_SECRET=...   (Gap 1 token test)
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GW_NS="${GW_NS:-mcp-gateway-system}"
BACKEND_NS="${BACKEND_NS:-mempalace}"
GATEWAY_URL="${GATEWAY_URL:-}"
pass(){ echo -e "  \033[0;32m✓\033[0m $1"; }
fail(){ echo -e "  \033[0;31m✗\033[0m $1"; }
info(){ echo -e "  \033[0;36mℹ\033[0m $1"; }

oc whoami >/dev/null 2>&1 || { fail "not logged in — run 'oc login' first"; exit 1; }
echo "== Logged in as $(oc whoami) @ $(oc whoami --show-server)"

# ---------------------------------------------------------------------------
echo ""; echo "== Gap 1 — OIDC AuthPolicy at the gateway edge =="
oc apply -f "$HERE/authpolicy-oidc.yaml" >/dev/null 2>&1 && pass "AuthPolicy applied" || fail "apply failed"
ENFORCED=$(oc get authpolicy mcp-auth-policy -n "$GW_NS" -o jsonpath='{.status.conditions[?(@.type=="Enforced")].status}' 2>/dev/null)
[ "$ENFORCED" = "True" ] && pass "AuthPolicy Enforced=True" || fail "AuthPolicy not Enforced (status: ${ENFORCED:-none})"

if [ -n "$GATEWAY_URL" ]; then
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GATEWAY_URL/mcp" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
  [ "$CODE" = "401" ] && pass "unauthenticated request rejected (401)" || fail "expected 401, got $CODE (auth may not be enforced on the path)"

  if [ -n "${KEYCLOAK_HOST:-}" ] && [ -n "${CLIENT_ID:-}" ] && [ -n "${CLIENT_SECRET:-}" ]; then
    TOKEN=$(curl -s -X POST "https://$KEYCLOAK_HOST/realms/${REALM}/protocol/openid-connect/token" \
      -d grant_type=client_credentials -d "client_id=$CLIENT_ID" -d "client_secret=$CLIENT_SECRET" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)
    if [ -n "$TOKEN" ]; then
      CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GATEWAY_URL/mcp" \
        -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
      [ "$CODE" = "200" ] && pass "authenticated request accepted (200)" || fail "expected 200 with token, got $CODE"
    else
      info "could not obtain token from Keycloak — skipping positive auth test"
    fi
  else
    info "KEYCLOAK_HOST/CLIENT_ID/CLIENT_SECRET unset — skipping positive auth test"
  fi
else
  info "GATEWAY_URL unset — skipping curl auth tests"
fi

# ---------------------------------------------------------------------------
echo ""; echo "== Gap 2 — backend bypass backstop (NetworkPolicy) =="
oc apply -f "$HERE/networkpolicy-backend-lockdown.yaml" >/dev/null 2>&1 && pass "NetworkPolicy applied" || fail "apply failed"
info "direct-access probe from a pod OUTSIDE the gateway ns (should TIME OUT):"
oc run np-probe --rm -i --restart=Never --image=registry.access.redhat.com/ubi9/ubi-minimal \
  -n default --command -- bash -c \
  "curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://mempalace.${BACKEND_NS}.svc.cluster.local:8000/health || echo TIMEOUT" 2>/dev/null | tail -1 | \
  grep -qE 'TIMEOUT|000' && pass "direct backend access blocked from outside gateway ns" || fail "backend reachable directly — NetworkPolicy not effective"

# ---------------------------------------------------------------------------
echo ""; echo "== Gap 3 — durable storage (StatefulSet + PVC) =="
info "This test is destructive-ish (deletes the MemPalace pod). Skips unless CONFIRM_G3=1."
if [ "${CONFIRM_G3:-0}" = "1" ]; then
  oc apply -f "$HERE/mempalace-statefulset-pvc.yaml" >/dev/null 2>&1 && pass "StatefulSet+PVC applied" || fail "apply failed"
  oc rollout status statefulset/mempalace -n "$BACKEND_NS" --timeout=120s >/dev/null 2>&1 && pass "StatefulSet ready" || fail "rollout not ready"
  PVC=$(oc get pvc -n "$BACKEND_NS" -l app=mempalace -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  [ "$PVC" = "Bound" ] && pass "PVC Bound" || fail "PVC not Bound (status: ${PVC:-none})"
  info "write a marker file, delete the pod, confirm it survives the restart:"
  oc exec -n "$BACKEND_NS" mempalace-0 -- sh -c 'echo durable > /opt/app-root/data/_verify_marker' 2>/dev/null
  oc delete pod mempalace-0 -n "$BACKEND_NS" >/dev/null 2>&1
  oc rollout status statefulset/mempalace -n "$BACKEND_NS" --timeout=120s >/dev/null 2>&1
  SURVIVED=$(oc exec -n "$BACKEND_NS" mempalace-0 -- cat /opt/app-root/data/_verify_marker 2>/dev/null)
  [ "$SURVIVED" = "durable" ] && pass "data survived pod restart — storage is durable" || fail "marker lost — storage not durable"
else
  info "set CONFIRM_G3=1 to run the destructive durability test"
fi
echo ""; echo "== done =="
