#!/usr/bin/env bash
# Build the demo image in-cluster (no local podman/registry) and deploy it.
# Uses a dedicated, non-Kueue namespace. Requires authenticated `oc`.
set -euo pipefail
NS=${NS:-maas-mcp-demo}
KC="https://mcp-keycloak.apps.ocp-gb.ibm.redhataicatalyst.com"
HERE="$(cd "$(dirname "$0")" && pwd)"

oc create namespace "$NS" 2>/dev/null || true
oc new-build --strategy=docker --binary --name=maas-mcp-demo -n "$NS" 2>/dev/null || true
oc start-build maas-mcp-demo --from-dir="$HERE" --follow -n "$NS"

# creds from cluster (no secrets in git)
LITELLM_KEY=$(oc get secret litemaas-litellm -n litemaas -o jsonpath='{.data.master-key}' | base64 -d)
AU=$(oc get secret mcp-keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d)
AP=$(oc get secret mcp-keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d)
AT=$(curl -sk -X POST "$KC/realms/master/protocol/openid-connect/token" -d grant_type=password -d client_id=admin-cli -d "username=$AU" -d "password=$AP" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
CID=$(curl -sk "$KC/admin/realms/mcp/clients?clientId=mcp-gateway-client" -H "Authorization: Bearer $AT" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
CS=$(curl -sk -X POST "$KC/admin/realms/mcp/clients/$CID/client-secret" -H "Authorization: Bearer $AT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
oc create secret generic maas-mcp-creds -n "$NS" \
  --from-literal=LITELLM_KEY="$LITELLM_KEY" --from-literal=MCP_CLIENT_SECRET="$CS" \
  --dry-run=client -o yaml | oc apply -n "$NS" -f -

oc apply -n "$NS" -f "$HERE/deploy.yaml"
# envFrom reads Secret values only when the pod starts; restart after rotating
# the Keycloak client secret so the hosted demo does not retain stale creds.
oc rollout restart deploy/maas-mcp-demo -n "$NS"
oc rollout status deploy/maas-mcp-demo -n "$NS" --timeout=180s
echo "URL: https://$(oc get route maas-mcp-demo -n "$NS" -o jsonpath='{.spec.host}')"
