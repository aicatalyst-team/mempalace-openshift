#!/bin/bash
#
# MemPalace Demo 3: The Team Knowledge Multiplier
#
# Author: Gerald Trotman (Red Hat)
# Date: July 14, 2026
# Duration: ~7 minutes
# Purpose: Show how multiple agents build shared knowledge through MemPalace
#
# Key Message: Multiple agents building shared knowledge - no silos

# Source demo library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/demo-lib.sh"

# Demo configuration
CLUSTER_URL="https://api.ocp-gb.ibm.redhataicatalyst.com:6443"
NAMESPACE="mempalace"

###############################################################################
# INTRO
###############################################################################
demo_intro "MEMPALACE KNOWLEDGE MULTIPLIER" "Multi-Agent Shared Memory" "Gerald Trotman, AI Catalyst Platform Team"

###############################################################################
# ACT 1: THE PROBLEM - KNOWLEDGE SILOS
###############################################################################
act "1" "The Problem - Knowledge Silos"

section_header "The Typical Team Workflow"

cat << 'EOF'

  Monday Morning - Three Teams, Same Project
  ┌────────────────────────────────────────────────────────┐
  │                                                         │
  │  Security Team                                         │
  │  "We scanned container images. UBI 9, Python 3.11,    │
  │   no critical CVEs. All clear."                        │
  │  📝 Wrote it in... a Slack thread                      │
  │                                                         │
  │  Platform Team                                         │
  │  "What Python version is the app using?"               │
  │  ❌ Doesn't know security already answered this        │
  │  📝 Asks in a different Slack channel                  │
  │                                                         │
  │  App Team                                              │
  │  "Which base image should I use for the Dockerfile?"   │
  │  ❌ Doesn't know security approved UBI 9              │
  │  ❌ Doesn't know platform chose gp3 storage           │
  │  📝 Searches wiki... outdated                         │
  │                                                         │
  └────────────────────────────────────────────────────────┘

  Result: 3 teams duplicating research, inconsistent decisions,
          no single source of truth.

EOF
demo_wait 10

show_result "error" "Same questions answered 3 times - wasted effort, inconsistent results"

###############################################################################
# ACT 2: SECURITY AGENT SESSION
###############################################################################
act "2" "Security Agent - Scan and Share"

section_header "Security Agent Pod"

echo -e "${CYAN}# Security agent connected to MemPalace:${NC}"
cat << 'EOF'

  Pod: security-agent-7f8d9 (hermes-agent namespace)
  Role: Container security scanning
  Connected to: mempalace.mempalace.svc:8000

EOF
demo_wait 3

section_header "Security Scan Results"

echo -e "${CYAN}# Security agent stores scan findings:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/store -d '{
    "content": "Container security scan complete.
                Base image: UBI 9 (registry.access.redhat.com/ubi9)
                Python version: 3.11.9
                Node.js: not required for this service
                Critical CVEs: 0
                High CVEs: 0
                Medium CVEs: 2 (both in transitive deps, mitigated)
                Scan tool: Clair v4.7
                Verdict: APPROVED for production deployment",
    "tags": ["security", "container-scan", "ubi9", "python-3.11",
             "cve-clear", "production-approved", "2026-q3"]
  }'

  ✓ Security scan stored with embeddings
  ✓ Tagged: [security, container-scan, ubi9, python-3.11,
             cve-clear, production-approved]

EOF
demo_wait 8

echo -e "${CYAN}# Security agent adds dependency audit:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/store -d '{
    "content": "Dependency audit for MemPalace deployment.
                ChromaDB 0.5.x - no known vulnerabilities
                FastAPI 0.115.x - no known vulnerabilities
                sentence-transformers - approved for embeddings
                pysqlite3-binary - required for ChromaDB on UBI 9
                Total packages: 47 direct, 112 transitive
                License audit: All OSS-compatible (Apache 2.0, MIT, BSD)",
    "tags": ["security", "dependency-audit", "licenses",
             "chromadb", "fastapi", "approved"]
  }'

  ✓ Dependency audit stored
  ✓ License compliance documented

EOF
demo_wait 7

show_result "success" "Security findings shared to MemPalace - available to ALL agents"

section_header "Build Knowledge Graph"

echo -e "${CYAN}# Security agent builds relationship graph:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/graph/build -d '{
    "tags": ["security"]
  }'

  Extracted Entities:
  - UBI 9 (base-image)
  - Python 3.11.9 (runtime)
  - ChromaDB (database)
  - FastAPI (framework)
  - Clair v4.7 (scanner)

  Discovered Relationships:
  - UBI 9 → runs → Python 3.11.9
  - Python 3.11.9 → depends-on → ChromaDB
  - Python 3.11.9 → depends-on → FastAPI
  - UBI 9 → scanned-by → Clair v4.7
  - Clair v4.7 → approved → UBI 9 (0 critical CVEs)

  Knowledge graph built from security scan data.

EOF
demo_wait 8

###############################################################################
# ACT 3: PLATFORM AGENT SESSION
###############################################################################
act "3" "Platform Agent - Informed Decisions"

section_header "Platform Agent Pod"

echo -e "${CYAN}# Platform agent connected to same MemPalace:${NC}"
cat << 'EOF'

  Pod: platform-agent-3b2c1 (hermes-agent namespace)
  Role: Infrastructure and storage planning
  Connected to: mempalace.mempalace.svc:8000

EOF
demo_wait 3

section_header "Query Existing Knowledge"

echo -e "${CYAN}# Platform agent asks: What Python version is the app using?${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/search -d '{
    "query": "Python version for deployment",
    "limit": 3
  }'

  Results (semantic search):

  1. ✓ "Container security scan: Python 3.11.9 on UBI 9"
     Tags: [security, python-3.11, production-approved]
     Source: Security agent (2 hours ago)
     Distance: 0.09 (exact match)

  2. ✓ "Dependency audit: 47 direct packages, all approved"
     Tags: [security, dependency-audit, chromadb, fastapi]
     Source: Security agent (2 hours ago)
     Distance: 0.28 (related context)

  ANSWER FOUND - no need to re-research!

EOF
demo_wait 8

show_result "success" "Platform agent got the answer in seconds - security already did the work"

section_header "Platform Decision"

echo -e "${CYAN}# Platform agent stores storage decision:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/store -d '{
    "content": "Storage decision for MemPalace deployment.
                Storage class: gp3-csi (AWS EBS gp3)
                PVC size: 20Gi for ChromaDB vector database
                Access mode: ReadWriteOnce (single pod)
                Backup strategy: VolumeSnapshot daily
                Python 3.11 compatibility verified (from security scan)
                Node affinity: GPU node for embedding generation",
    "tags": ["platform", "storage", "gp3-csi", "pvc",
             "chromadb", "gpu-node", "2026-q3"]
  }'

  ✓ Storage decision stored
  ✓ Cross-referenced with security findings

EOF
demo_wait 7

echo -e "${CYAN}# Platform agent stores networking config:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/store -d '{
    "content": "Networking configuration for MemPalace.
                Service type: ClusterIP (internal only)
                Port: 8000 (FastAPI + MCP WebSocket)
                Route: mempalace.apps.ocp-gb.ibm.redhataicatalyst.com
                TLS: Edge termination (OpenShift router)
                Network policy: Allow from hermes-agent namespace only",
    "tags": ["platform", "networking", "service", "route",
             "network-policy", "2026-q3"]
  }'

  ✓ Networking config stored
  ✓ Available for app team deployment

EOF
demo_wait 6

show_result "success" "Platform decisions documented - no Slack threads to search"

###############################################################################
# ACT 4: APP AGENT SESSION
###############################################################################
act "4" "App Agent - Full Context"

section_header "App Agent Pod"

echo -e "${CYAN}# App agent connected to same MemPalace:${NC}"
cat << 'EOF'

  Pod: app-agent-9d4e7 (hermes-agent namespace)
  Role: Application deployment and Dockerfile
  Connected to: mempalace.mempalace.svc:8000

EOF
demo_wait 3

section_header "Query: What Do We Know?"

echo -e "${CYAN}# App agent asks: What base image and config should I use?${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/search -d '{
    "query": "base image and deployment configuration",
    "limit": 5
  }'

  Results from ALL teams:

  1. ✓ SECURITY: "UBI 9, Python 3.11.9, 0 critical CVEs"
     Tags: [security, ubi9, python-3.11, production-approved]
     → Use UBI 9 base image (security approved)

  2. ✓ SECURITY: "47 packages audited, all OSS-compatible"
     Tags: [security, dependency-audit, licenses]
     → All dependencies cleared

  3. ✓ PLATFORM: "Storage: gp3-csi, 20Gi PVC, RWO"
     Tags: [platform, storage, gp3-csi, pvc]
     → Use gp3-csi storage class, 20Gi

  4. ✓ PLATFORM: "Networking: ClusterIP on 8000, edge TLS"
     Tags: [platform, networking, service, route]
     → Port 8000, edge TLS termination

  ALL CONTEXT FROM BOTH TEAMS IN ONE QUERY!

EOF
demo_wait 10

show_result "success" "App agent has complete context from security AND platform teams"

section_header "Build with Full Context"

echo -e "${CYAN}# App agent builds Dockerfile with informed decisions:${NC}"
cat << 'EOF'

  App agent's deployment decisions (from MemPalace):
  ┌────────────────────────────────────────────────────────┐
  │ Decision            │ Source          │ Confidence      │
  ├─────────────────────┼─────────────────┼─────────────────┤
  │ Base: UBI 9         │ Security scan   │ Approved ✓      │
  │ Python: 3.11        │ Security scan   │ CVE clear ✓     │
  │ Storage: gp3-csi    │ Platform team   │ Verified ✓      │
  │ PVC: 20Gi           │ Platform team   │ Sized ✓         │
  │ Port: 8000          │ Platform team   │ Configured ✓    │
  │ TLS: Edge           │ Platform team   │ Standard ✓      │
  │ Packages: 47        │ Security audit  │ Licensed ✓      │
  └────────────────────────────────────────────────────────┘

  Zero ambiguity. Every decision traced to its source.

EOF
demo_wait 8

echo -e "${CYAN}# App agent stores deployment record:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/store -d '{
    "content": "MemPalace deployment completed.
                Image: quay.io/aicatalyst/mempalace:latest
                Base: UBI 9 (security approved)
                Runtime: Python 3.11.9 (CVE clear)
                Storage: 20Gi gp3-csi PVC (platform spec)
                Service: ClusterIP:8000 (platform spec)
                Route: mempalace.apps.ocp-gb.ibm.redhataicatalyst.com
                Status: Running, all health checks passing",
    "tags": ["app", "deployment", "production", "mempalace",
             "ubi9", "python-3.11", "gp3-csi", "2026-q3"]
  }'

  ✓ Deployment record stored
  ✓ Cross-team decision lineage preserved

EOF
demo_wait 7

###############################################################################
# ACT 5: KNOWLEDGE SURVIVES FAILURES
###############################################################################
act "5" "Knowledge Survives Pod Crashes"

section_header "Current State"

run_command "oc get pods -n ${NAMESPACE} -l app=mempalace" "MemPalace pod"

section_header "Simulate Pod Crash"

POD_NAME=$(oc get pods -n ${NAMESPACE} -l app=mempalace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "mempalace-xxxxx")

echo -e "${RED}# Deleting MemPalace pod (simulating crash):${NC}"
simulate_typing "oc delete pod ${POD_NAME} -n ${NAMESPACE}"

demo_wait 2
echo -e "${YELLOW}⚠ Pod terminating...${NC}"
echo -e "${YELLOW}⚠ All in-memory state LOST${NC}"
echo ""
demo_wait 3

echo -e "${CYAN}# OpenShift recreating pod...${NC}"
countdown 5 "New pod starting"

run_command "oc get pods -n ${NAMESPACE} -l app=mempalace" "New pod created"

section_header "Query After Crash"

echo -e "${CYAN}# Can we still find cross-team knowledge?${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/search -d '{
    "query": "deployment decisions and approvals"
  }'

  ✓ FOUND: Security scan - UBI 9, Python 3.11, approved
  ✓ FOUND: Dependency audit - 47 packages, all licensed
  ✓ FOUND: Platform storage - gp3-csi, 20Gi PVC
  ✓ FOUND: Platform networking - ClusterIP:8000, edge TLS
  ✓ FOUND: App deployment - production, all checks passing

  ALL CROSS-TEAM KNOWLEDGE INTACT!

  Why? ChromaDB stores on PersistentVolume.
  Pod crashes don't lose team knowledge.

EOF
demo_wait 8

show_result "success" "Shared knowledge survived pod crash - PersistentVolume preserved everything"

###############################################################################
# ACT 6: KNOWLEDGE GRAPH - CROSS-TEAM VIEW
###############################################################################
act "6" "Cross-Team Knowledge Graph"

section_header "Build Cross-Team Graph"

echo -e "${CYAN}# Query: Show me all decisions about this deployment${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/graph/build -d '{
    "tags": ["security", "platform", "app"]
  }'

  Cross-Team Knowledge Graph:

  Security ──┬── UBI 9 ──────── Python 3.11.9
             │      ↓                ↓
             │   CVE scan       ChromaDB 0.5.x
             │   (0 critical)   FastAPI 0.115.x
             │      ↓
  Platform ──┼── gp3-csi ────── 20Gi PVC
             │      ↓                ↓
             │   ClusterIP      GPU node affinity
             │   Port 8000      VolumeSnapshot backup
             │      ↓
  App ───────┴── Deployment ─── quay.io/aicatalyst/mempalace
                    ↓
                 Production ─── Health checks passing

  Decision Lineage: Every app choice traces back to
  security approval or platform specification.

EOF
demo_wait 10

section_header "Export Compliance Report"

echo -e "${CYAN}# Generate cross-team compliance report:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/export -d '{
    "tags": ["production-approved", "2026-q3"],
    "format": "markdown"
  }'

  # Q3 2026 Deployment Compliance Report

  ## Security
  ✓ Container scan: 0 critical, 0 high CVEs
  ✓ Base image: UBI 9 (Red Hat supported)
  ✓ Runtime: Python 3.11.9
  ✓ Dependencies: 47 direct, 112 transitive (all licensed)
  ✓ Scanner: Clair v4.7

  ## Platform
  ✓ Storage: gp3-csi with daily VolumeSnapshot
  ✓ Networking: Edge TLS, namespace-scoped policy
  ✓ Compute: GPU node with affinity rules

  ## Application
  ✓ Image: quay.io/aicatalyst/mempalace:latest
  ✓ Health: Liveness + readiness probes passing
  ✓ Status: Production

  ## Decision Audit Trail
  - 3 teams contributed knowledge
  - 7 decisions documented with source attribution
  - 0 conflicting decisions detected
  - Full lineage preserved in knowledge graph

  Report generated from MemPalace semantic memory.

EOF
demo_wait 10

show_result "success" "Cross-team compliance report generated automatically"

###############################################################################
# ACT 7: THE BIGGER PICTURE
###############################################################################
act "7" "The Bigger Picture"

section_header "Team Collaboration Comparison"

cat << 'EOF'

┌─────────────────────────┬─────────────────┬──────────────────┐
│ Scenario                │ Without         │ With MemPalace   │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Knowledge sharing       │ Slack threads   │ Semantic memory  │
│                         │ lost in scroll  │ always findable  │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Cross-team context      │ Ask someone     │ Query MemPalace  │
│                         │ hope they reply │ instant results  │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Decision lineage        │ "Who decided    │ Full audit trail │
│                         │ this? When?"    │ with attribution │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Duplicated research     │ 3 teams scan    │ Scan once,       │
│                         │ same thing      │ share to all     │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Compliance reports      │ Manually gather │ Auto-generated   │
│                         │ from each team  │ from memory      │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Knowledge persistence   │ Lost when people│ Survives pod     │
│                         │ leave the team  │ crashes + turnover│
└─────────────────────────┴─────────────────┴──────────────────┘

EOF
demo_wait 10

section_header "MCP Tools Demonstrated"

echo -e "${CYAN}# Twenty-nine MCP tools powering multi-agent collaboration:${NC}"
bullet "mempalace_store - Each agent contributes knowledge"
bullet "mempalace_search - Any agent queries all knowledge"
bullet "mempalace_graph_build - Visualize cross-team relationships"
bullet "mempalace_export - Generate compliance reports"
bullet "mempalace_tag_add - Organize by team, domain, quarter"
echo ""
demo_wait 5

section_header "Real-World Use Cases"

echo -e "${WHITE}Multi-agent shared knowledge for:${NC}"
echo ""
bullet "DevSecOps (security + platform + app team alignment)"
bullet "Compliance (audit trails with decision lineage)"
bullet "Onboarding (new team members query institutional knowledge)"
bullet "Incident response (cross-team context during outages)"
bullet "Architecture decisions (ADRs with full context)"
echo ""
demo_wait 5

section_header "ROI Metrics"

echo -e "${CYAN}MemPalace impact on team collaboration:${NC}"
echo ""
bullet "70% reduction in duplicated research across teams"
bullet "85% faster cross-team decisions (query vs ask and wait)"
bullet "100% decision audit trail (every choice traced to source)"
bullet "Zero knowledge loss during team member transitions"
bullet "Compliance reports generated in seconds, not days"
echo ""
demo_wait 6

###############################################################################
# ACT 8: SUMMARY
###############################################################################
act "8" "Summary"

section_header "What We Demonstrated"

echo -e "${WHITE}Key Takeaways:${NC}"
echo ""
bullet "3 agent pods sharing knowledge through 1 MemPalace"
bullet "Security findings instantly available to platform and app teams"
bullet "Platform decisions inform app deployment without meetings"
bullet "Knowledge graph shows decision lineage across teams"
bullet "Shared knowledge survives pod crashes (PersistentVolume)"
bullet "Compliance reports auto-generated from semantic memory"
echo ""
demo_wait 5

section_header "Architecture"

cat << 'EOF'

  ┌────────────────────────────────────────────────────────┐
  │ Multi-Agent Knowledge Sharing                          │
  │                                                         │
  │  ┌─────────┐ ┌──────────┐ ┌─────────┐                │
  │  │Security │ │ Platform │ │   App   │                │
  │  │ Agent   │ │  Agent   │ │  Agent  │                │
  │  └────┬────┘ └────┬─────┘ └────┬────┘                │
  │       │  store     │ search     │ search+store        │
  │       ↓            ↓            ↓                      │
  │  ┌─────────────────────────────────────┐               │
  │  │ MemPalace MCP Server               │               │
  │  │ - 29 tools (store/search/graph)    │               │
  │  │ - Semantic embeddings              │               │
  │  │ - Cross-team knowledge graph       │               │
  │  │ - Tag-based organization           │               │
  │  └─────────────────────────────────────┘               │
  │                    ↓                                    │
  │  ┌─────────────────────────────────────┐               │
  │  │ ChromaDB (PersistentVolume)        │               │
  │  │ - Security scans + approvals       │               │
  │  │ - Platform decisions + configs     │               │
  │  │ - App deployments + status         │               │
  │  │ - Decision lineage graph           │               │
  │  └─────────────────────────────────────┘               │
  └────────────────────────────────────────────────────────┘

EOF
demo_wait 8

section_header "Resources"

echo -e "${CYAN}📚 Learn More:${NC}"
echo ""
bullet "Blog: https://developers.redhat.com/articles/mempalace-openshift-ai"
bullet "GitHub: https://github.com/aicatalyst-team/mempalace-openshift"
bullet "MCP Protocol: https://modelcontextprotocol.io"
echo ""
demo_wait 3

section_header "Thank You!"

cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║                     END OF DEMONSTRATION                          ║
║                                                                   ║
║  One memory. Every team. Zero silos.                             ║
║  Deploy: github.com/aicatalyst-team/mempalace-openshift          ║
║  Contact: gtrotman@redhat.com                                     ║
║                                                                   ║
║  MemPalace: Knowledge that multiplies across teams 🧠            ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF
