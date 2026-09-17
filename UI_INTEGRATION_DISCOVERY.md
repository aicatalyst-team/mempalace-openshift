# OpenShift AI MCP Server UI Integration — Discovery Summary

**Date:** September 15, 2026  
**Status:** Verified live on api.ocp-gb.ibm.redhataicatalyst.com (OpenShift AI 3.5)  
**Key Finding:** OpenShift AI 3.5 has separate MCP UI paths. The native AI Hub MCP Catalog is gated by the dashboard `mcpCatalog` feature flag and reads model-catalog MCP sources. The Gen AI chat MCP selector reads a different ConfigMap with one JSON object per key.

---

## The Question

How are custom MCP servers made discoverable in the OpenShift AI dashboard ("AI hub")? The blog mentioned the feature exists, but the mechanics were undocumented.

## The Answer: Three Registration Paths

Custom MCP servers on OpenShift AI may use three separate registrations, each with a different purpose:

### 1. Federation Registration (Gateway/Routing)
**CRD:** `MCPServerRegistration` (Kuadrant)  
**Namespace:** `mcp-gateway-system`  
**Purpose:** Tells the Kuadrant MCP Gateway where to find the server, which tools it exposes, and how to route/authorize them.

```yaml
apiVersion: mcp.kuadrant.io/v1alpha1
kind: MCPServerRegistration
metadata:
  name: mempalace
  namespace: mcp-gateway-system
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: mempalace-mcp-route
  category: ["memory", "knowledge-management"]
  hint: "AI memory system..."
  tags: ["ai-memory", "chromadb", "semantic-search"]
  path: /mcp
  # ... more fields
```

**Who consumes this:** The MCP Gateway operator and the running gateway pods. They use it to federate tools.

### 2. Native AI Hub MCP Catalog
**Feature flag:** `spec.dashboardConfig.mcpCatalog: true` on `OdhDashboardConfig`
**Namespace:** `redhat-ods-applications` for the dashboard CR
**Purpose:** Enables the separate **MCP servers** tab beside Models under AI Hub.

The catalog is served by the model-catalog backend. User-owned entries belong in the `mcp-catalog-sources` ConfigMap in `rhoai-model-registries`, using an `mcp_catalogs` source and a catalog YAML file. See `aramco-mcp-lifecycle/hardening/native-mcp-catalog-registration.yaml`.

### 3. Gen AI Chat MCP Selector
**Mechanism:** `ConfigMap` named `gen-ai-aa-mcp-servers`  
**Namespace:** `redhat-ods-applications`  
**Purpose:** Supplies MCP connections that users can select in the Gen AI chat experience.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gen-ai-aa-mcp-servers
  namespace: redhat-ods-applications
data:
  mempalace: |
    {
      "url": "https://mcp-secure.apps.ocp-gb.ibm.redhataicatalyst.com/mcp",
      "transport": "streamable-http",
      "description": "MemPalace semantic memory MCP server for the Saudi Aramco OpenShift AI demo"
    }
```

**Who consumes this:** The `gen-ai-ui` deployment and its BFF. It reads this ConfigMap for the chat MCP selector. The current BFF does not accept the older `servers.json` array format.

---

## Discovery Process

### How I Found It

1. **Started with:** "The dashboard has an MCP servers section, but MemPalace isn't listed. Where's the integration point?"

2. **Searched cluster config:**
   - Checked CRDs: Found `mcpserverregistrations.mcp.kuadrant.io` ✓
   - Checked if there was an `mcp-catalog` CRD: No ✗
   - Checked ModelRegistry pattern (how models are discovered): Found `modelregistries.opendatahub.io` ✓

3. **Checked gen-ai-ui deployment:**
   - Found `odh-mod-arch-gen-ai` container
   - Read logs for clues

4. **Found the smoking gun in logs:**
   ```
   ERROR msg="failed to get ConfigMap" 
   error="configmaps \"gen-ai-aa-mcp-servers\" not found" 
   namespace=redhat-ods-applications
   ```
   
   The UI was *trying* to read a ConfigMap that didn't exist yet. On the current cluster, the same component also logged a parse error when the ConfigMap contained a `servers.json` array; the current schema is one JSON object per ConfigMap key.

5. **Verified the current platform paths:**
   - Enabled `mcpCatalog` on `OdhDashboardConfig`
   - Confirmed the native API returns the built-in MCP catalogs
   - Added MemPalace to the user MCP catalog source
   - Confirmed the Gen AI BFF returns MemPalace as a healthy chat MCP server

---

## Why This Design?

1. **Separation of concerns:**
   - The gateway manages federation (tool availability, routing, authorization)
   - The dashboard manages discovery (what users see, what to promote)

2. **Operational flexibility:**
   - An operator can disable a server in the native catalog or chat selector without removing it from the gateway (the MCPServerRegistration stays)
   - An operator can add catalog metadata without modifying the gateway's routing rules

3. **No custom CRDs for metadata:**
   - The ConfigMap is standard Kubernetes, familiar to all operators
   - No webhook validation, no controller logic — just JSON data

4. **Extensibility:**
   - Multiple servers are additional catalog entries or ConfigMap keys
   - Future servers can use the same gateway registration plus whichever UI path they need

---

## Manifests and Runbook Updates

### New Artifacts
- **`aramco-mcp-lifecycle/hardening/ui-catalog-registration.yaml`** — Gen AI chat MCP selector ConfigMap
- **`aramco-mcp-lifecycle/hardening/native-mcp-catalog-registration.yaml`** — Native AI Hub MCP Catalog source and MemPalace entry

### Updated Documentation
- **`demos/MCP_LIFECYCLE_RUNBOOK.md`** — Phase 1.3 now explains the UI discovery mechanism and references the manifest
- **`aramco-mcp-lifecycle/BLOG_FULLSTACK_MCP_MAAS.md`** — New section explaining dual-path registration (federation vs. UI)
- **`demos/mcp-gateway-lifecycle-demo.sh`** — canonical Act-based presenter flow verifies federation, OIDC, MaaS, MLflow, and UI discovery

---

## Live Verification

**Cluster:** https://api.ocp-gb.ibm.redhataicatalyst.com:6443  
**Date Verified:** 2026-09-15  

### Step-by-Step

1. **Enabled the native MCP tab:**
   ```bash
   oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
     --type=merge -p '{"spec":{"dashboardConfig":{"mcpCatalog":true}}}'
   ```

2. **Applied the two MCP registrations:**
   ```bash
   oc apply -f aramco-mcp-lifecycle/hardening/ui-catalog-registration.yaml
   oc apply -f aramco-mcp-lifecycle/hardening/native-mcp-catalog-registration.yaml
   ```

3. **Checked the native catalog API:**
   ```bash
   curl -H "Authorization: Bearer $(oc whoami -t)" \
     'https://rh-ai.apps.ocp-gb.ibm.redhataicatalyst.com/model-registry/api/v1/mcp_catalog/mcp_servers?namespace=rhoai-model-registries'
   # ✓ Includes the MemPalace entry under aramco_mcp_servers
   ```

4. **Verified the UI:**
   - Navigated to: https://rh-ai.apps.ocp-gb.ibm.redhataicatalyst.com/
   - Hard-refreshed the dashboard
   - AI Hub → Models / MCP servers
   - ✓ The MCP servers tab is visible and MemPalace is listed

---

## Gen AI Chat ConfigMap Schema (Verified on OpenShift AI 3.5)

The ConfigMap should contain one JSON object per server key:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| ConfigMap key | string | Yes | Server label, for example `mempalace` |
| `url` | string | Yes | Full MCP endpoint URL |
| `transport` | string | No | `streamable-http` or `sse`; defaults to `streamable-http` |
| `description` | string | No | Short description shown in the selector |
| `logo` | string | No | Optional logo URL |

The native catalog uses the separate YAML schema in `native-mcp-catalog-registration.yaml`, including `mcp_servers`, `deploymentMode`, `endpoints`, and `tools`.

---

## Next Steps

1. **Test end-to-end:** Verify that developers can open the native MCP Catalog and select MemPalace in the Gen AI chat MCP selector.

2. **Document in Red Hat docs:** This pattern should be in the official OpenShift AI documentation for operators registering custom MCP servers.

3. **Extend for multiple servers:** Add a native catalog entry and a separate chat ConfigMap key for each future custom MCP server.

4. **Monitor for GA improvements:** When Kuadrant AuthPolicy GA's and the Tech Preview OIDC defect is fixed, the federation path may gain UI-integrated policy management.

---

## Files Changed

- ✅ **Created:** `aramco-mcp-lifecycle/hardening/ui-catalog-registration.yaml` (ConfigMap manifest)
- ✅ **Updated:** `demos/MCP_LIFECYCLE_RUNBOOK.md` (Phase 1.3: UI discovery)
- ✅ **Updated:** `aramco-mcp-lifecycle/BLOG_FULLSTACK_MCP_MAAS.md` (dual-path registration section)
- ✅ **Updated:** `aramco-mcp-lifecycle/mcp-gateway-lifecycle-demo.sh` (full-stack Act flow; `demos/` is the canonical wrapper)
- ✅ **Added to memory:** `reference_mcp_ui_discovery_configmap.md` (for future sessions)

---

**Repository:** https://github.com/aicatalyst-team/mempalace-openshift  
**Key commits:** 746bd25, 75fb909
