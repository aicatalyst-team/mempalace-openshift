#!/usr/bin/env bash
# Run the MaaS LLM <-> MCP round-trip demo. Derives all credentials from the
# cluster (nothing secret is stored in git). Requires an authenticated `oc`.
#   ./run.sh ["your task prompt"]
set -euo pipefail
KC="https://mcp-keycloak.apps.ocp-gb.ibm.redhataicatalyst.com"

# LiteLLM (MaaS) master key
export LITELLM_KEY=$(oc get secret litemaas-litellm -n litemaas -o jsonpath='{.data.master-key}' | base64 -d)

# mcp realm client secret (via RHBK admin API using the operator's initial-admin)
AU=$(oc get secret mcp-keycloak-initial-admin -n keycloak -o jsonpath='{.data.username}' | base64 -d)
AP=$(oc get secret mcp-keycloak-initial-admin -n keycloak -o jsonpath='{.data.password}' | base64 -d)
AT=$(curl -sk -X POST "$KC/realms/master/protocol/openid-connect/token" -d grant_type=password -d client_id=admin-cli -d "username=$AU" -d "password=$AP" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
CID=$(curl -sk "$KC/admin/realms/mcp/clients?clientId=mcp-gateway-client" -H "Authorization: Bearer $AT" | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["id"])')
export MCP_CLIENT_SECRET=$(curl -sk -X POST "$KC/admin/realms/mcp/clients/$CID/client-secret" -H "Authorization: Bearer $AT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')

[ "${1:-}" = "--seed" ] && { python3 "$(dirname "$0")/seed.py"; shift; }
python3 "$(dirname "$0")/agent.py" "${1:-Search my memory palace for how OIDC authentication is enforced on the MCP gateway, then summarize in two sentences.}"
