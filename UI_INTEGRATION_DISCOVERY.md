# OpenShift AI MCP Server UI Integration — Discovery Summary

**Date:** September 15, 2026  
**Status:** Verified live on api.ocp-gb.ibm.redhataicatalyst.com (OpenShift AI 3.5)  
**Key Finding:** The platform-native integration mechanism is **ConfigMap-based, not CRD-based**.

---

## The Question

How are custom MCP servers made discoverable in the OpenShift AI dashboard ("AI hub")? The blog mentioned the feature exists, but the mechanics were undocumented.

## The Answer: Dual-Path Registration

Custom MCP servers on OpenShift AI require two separate registrations, each with a different purpose:

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

### 2. UI Discovery Registration (Dashboard/Catalog)
**Mechanism:** `ConfigMap` named `gen-ai-aa-mcp-servers`  
**Namespace:** `redhat-ods-applications`  
**Purpose:** Tells the OpenShift AI dashboard which MCP servers to list in the "AI hub" and what metadata to display.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gen-ai-aa-mcp-servers
  namespace: redhat-ods-applications
data:
  servers.json: |
    [
      {
        "name": "MemPalace",
        "id": "mempalace",
        "description": "...",
        "category": ["memory", "knowledge-management"],
        "tags": ["ai-memory", "chromadb", "semantic-search"],
        "serverAddress": "http://mempalace.mempalace.svc.cluster.local:8000/mcp",
        "documentationUrl": "https://...",
        "icon": "🏛️"
      }
    ]
```

**Who consumes this:** The `gen-ai-ui` deployment. It reads this ConfigMap at startup and watches for updates. It displays the servers in the dashboard's "MCP servers" section.

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
   
   The UI was *trying* to read a ConfigMap that didn't exist yet.

5. **Verified the pattern:**
   - Created the ConfigMap with MemPalace metadata
   - Restarted gen-ai-ui
   - Confirmed logs no longer show the error
   - MemPalace now discoverable in the dashboard

---

## Why This Design?

1. **Separation of concerns:**
   - The gateway manages federation (tool availability, routing, authorization)
   - The dashboard manages discovery (what users see, what to promote)

2. **Operational flexibility:**
   - An operator can disable a server in the dashboard (remove it from ConfigMap) without removing it from the gateway (the MCPServerRegistration stays)
   - An operator can add descriptive metadata (icon, category, tags) without modifying the gateway's routing rules

3. **No custom CRDs for metadata:**
   - The ConfigMap is standard Kubernetes, familiar to all operators
   - No webhook validation, no controller logic — just JSON data

4. **Extensibility:**
   - Multiple servers are just additional entries in the JSON array
   - Future servers follow the same pattern: one MCPServerRegistration + one servers.json entry

---

## Manifests and Runbook Updates

### New Artifact
- **`aramco-mcp-lifecycle/hardening/ui-catalog-registration.yaml`** — Ready-to-apply ConfigMap for MemPalace

### Updated Documentation
- **`demos/MCP_LIFECYCLE_RUNBOOK.md`** — Phase 1.3 now explains the UI discovery mechanism and references the manifest
- **`aramco-mcp-lifecycle/BLOG_FULLSTACK_MCP_MAAS.md`** — New section explaining dual-path registration (federation vs. UI)
- **`demos/mcp-gateway-lifecycle-demo.sh`** — Phase 1 now verifies both federation (CRD) and UI discovery (ConfigMap)

---

## Live Verification

**Cluster:** https://api.ocp-gb.ibm.redhataicatalyst.com:6443  
**Date Verified:** 2026-09-15  

### Step-by-Step

1. **Applied the ConfigMap:**
   ```bash
   oc apply -f aramco-mcp-lifecycle/hardening/ui-catalog-registration.yaml
   ```

2. **Restarted the gen-ai-ui:**
   ```bash
   oc rollout restart deploy/gen-ai-ui -n redhat-ods-applications
   oc rollout status deploy/gen-ai-ui -n redhat-ods-applications --timeout=120s
   ```

3. **Checked logs for errors:**
   ```bash
   oc logs -n redhat-ods-applications deploy/gen-ai-ui --tail=50 | grep "gen-ai-aa-mcp-servers"
   # ✓ No "failed to get ConfigMap" errors
   ```

4. **Verified UI:**
   - Navigated to: https://rh-ai.apps.ocp-gb.ibm.redhataicatalyst.com/
   - AI hub → MCP servers
   - ✓ MemPalace now listed with icon, category, description, and tags

---

## ConfigMap Schema (Inferred from Live Testing)

The `servers.json` in the ConfigMap should be a JSON array with objects having:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `name` | string | Yes | Display name in the UI |
| `id` | string | Yes | Unique identifier, kebab-case |
| `description` | string | Yes | Short description for the catalog |
| `category` | array | Yes | Categories for filtering (e.g., `["memory", "knowledge-management"]`) |
| `tags` | array | No | Tags for search/discovery |
| `serverAddress` | string | Yes | Full MCP endpoint URL (in-cluster Service is fine) |
| `registeredTools` | array | No | List of tool names this server exposes |
| `documentationUrl` | string | No | Link to docs/repo |
| `icon` | string | No | Emoji or icon identifier |

---

## Next Steps

1. **Test end-to-end:** Verify that developers can click on MemPalace in the AI hub and deploy/interact with it.

2. **Document in Red Hat docs:** This pattern should be in the official OpenShift AI documentation for operators registering custom MCP servers.

3. **Extend for multiple servers:** The ConfigMap JSON array can hold multiple servers — future custom MCP servers will use the same pattern.

4. **Monitor for GA improvements:** When Kuadrant AuthPolicy GA's and the Tech Preview OIDC defect is fixed, the federation path may gain UI-integrated policy management.

---

## Files Changed

- ✅ **Created:** `aramco-mcp-lifecycle/hardening/ui-catalog-registration.yaml` (ConfigMap manifest)
- ✅ **Updated:** `demos/MCP_LIFECYCLE_RUNBOOK.md` (Phase 1.3: UI discovery)
- ✅ **Updated:** `aramco-mcp-lifecycle/BLOG_FULLSTACK_MCP_MAAS.md` (dual-path registration section)
- ✅ **Updated:** `demos/mcp-gateway-lifecycle-demo.sh` (Phase 1: verify both paths)
- ✅ **Added to memory:** `reference_mcp_ui_discovery_configmap.md` (for future sessions)

---

**Repository:** https://github.com/aicatalyst-team/mempalace-openshift  
**Key commits:** 746bd25, 75fb909
