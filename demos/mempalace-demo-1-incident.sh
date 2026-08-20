#!/bin/bash
#
# MemPalace Demo 1: The Incident Knowledge Base
#
# Author: Gerald Trotman (Red Hat)
# Date: July 6, 2026
# Duration: ~5 minutes
# Purpose: Show how MemPalace prevents knowledge loss during incidents
#
# Key Message: Institutional memory that survives team turnover

# Source demo library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/demo-lib.sh"

# Demo configuration
CLUSTER_URL="https://api.ocp-gb.ibm.redhataicatalyst.com:6443"
NAMESPACE="mempalace"

###############################################################################
# INTRO
###############################################################################
demo_intro "MEMPALACE INCIDENT KNOWLEDGE" "Institutional Memory Demo" "Gerald Trotman, AI Catalyst Platform Team"

###############################################################################
# ACT 1: THE PROBLEM - LOST KNOWLEDGE
###############################################################################
act "1" "The Problem - Lost Knowledge"

section_header "The Typical Incident Response"

cat << 'EOF'

  3:00 AM - PagerDuty Alert
  ┌────────────────────────────────────────────────────────┐
  │ 🚨 CRITICAL: Redis Connection Timeout                 │
  │ Service: payment-api                                   │
  │ Error: connection pool exhausted                       │
  └────────────────────────────────────────────────────────┘

  Junior Engineer on-call:
  ❌ Searches Slack: "redis timeout" - nothing relevant
  ❌ Searches JIRA: finds 12 tickets, none match
  ❌ Searches wiki: outdated, last updated 2 years ago
  ❌ Escalates to senior engineer (wakes them up)

  Senior Engineer (sleepy):
  "Oh yeah, we hit this 6 months ago. Just increase the
   connection pool size. It's in the ConfigMap."

  Problem: Knowledge was in someone's HEAD, not searchable.

EOF
demo_wait 12

show_result "error" "Incident took 45 minutes because knowledge wasn't captured"

###############################################################################
# ACT 2: MEMPALACE HAS INSTITUTIONAL MEMORY
###############################################################################
act "2" "MemPalace Has Institutional Memory"

section_header "Check MemPalace Deployment"

run_command "oc get pods -n ${NAMESPACE}" "MemPalace server status"

section_header "Past Incidents Already Stored"

echo -e "${CYAN}# Query MemPalace for Redis incidents:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/search \
    -d '{"query": "Redis connection timeout errors"}'

  Results (semantic search):

  1. ✓ "Redis timeout - connection pool fix"
     Tags: [redis, timeout, connection-pool, resolved]
     Date: 6 months ago
     Solution: "Increased maxConnections from 10 to 50 in ConfigMap"
     Distance: 0.12 (very similar)

  2. ✓ "Database connection exhaustion pattern"
     Tags: [database, connections, performance]
     Solution: "Monitor connection pool metrics, set limits"
     Distance: 0.31 (similar concept)

  3. ✓ "Connection pool tuning for high traffic"
     Tags: [scaling, connections, best-practice]
     Guide: "Connection pool = (cores × 2) + effective_spindle_count"
     Distance: 0.45 (related)

EOF
demo_wait 12

show_result "success" "Found 3 related incidents - NO senior engineer needed!"

section_header "Semantic Search Explained"

echo -e "${CYAN}# Why it worked:${NC}"
bullet "Query: 'Redis connection timeout errors'"
bullet "Match 1: 'connection pool' mapped to 'timeout' (synonym)"
bullet "Match 2: 'exhaustion' mapped to 'errors' (concept match)"
bullet "Match 3: 'tuning' mapped to 'fix' (related action)"
echo ""
demo_wait 8

highlight "Semantic search finds meaning, not just keywords"

###############################################################################
# ACT 3: APPLY THE FIX
###############################################################################
act "3" "Apply the Fix"

section_header "Junior Engineer Uses Past Solution"

echo -e "${CYAN}# Applying the fix from 6 months ago:${NC}"
simulate_typing "oc get configmap payment-api-config -n production -o yaml"

demo_wait 4
cat << 'EOF'

  Current Config:
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: payment-api-config
  data:
    REDIS_MAX_CONNECTIONS: "10"    # Too low!
    REDIS_TIMEOUT: "5000"

EOF
demo_wait 6

echo -e "${CYAN}# Increase connection pool (from MemPalace solution):${NC}"
simulate_typing "oc patch configmap payment-api-config -p '{\"data\":{\"REDIS_MAX_CONNECTIONS\":\"50\"}}'"

demo_wait 3
echo -e "${GREEN}✓ ConfigMap updated${NC}"
echo -e "${GREEN}✓ Pods restarting with new config${NC}"
echo ""
demo_wait 4

echo -e "${CYAN}# Wait for rollout:${NC}"
countdown 3 "Pods restarting"

cat << 'EOF'

  ✓ Errors stopped
  ✓ Connection pool metrics healthy
  ✓ Incident resolved in 5 minutes (not 45!)
  ✓ Senior engineer still sleeping

EOF
demo_wait 8

show_result "success" "Junior engineer solved it WITHOUT escalation"

###############################################################################
# ACT 4: THE PERSISTENCE TEST
###############################################################################
act "4" "Knowledge Survives Pod Crashes"

section_header "Current Pod State"

POD_NAME=$(oc get pods -n ${NAMESPACE} -l app=mempalace -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "mempalace-xxxxx")

run_command "oc get pods -n ${NAMESPACE} -l app=mempalace" "MemPalace pod"

section_header "Simulate Pod Crash"

echo -e "${RED}# Deleting MemPalace pod (simulating crash):${NC}"
simulate_typing "oc delete pod ${POD_NAME} -n ${NAMESPACE}"

demo_wait 3
echo -e "${YELLOW}⚠ Pod terminating...${NC}"
echo -e "${YELLOW}⚠ All in-memory state LOST${NC}"
echo ""
demo_wait 4

echo -e "${CYAN}# OpenShift recreating pod...${NC}"
countdown 5 "New pod starting"

run_command "oc get pods -n ${NAMESPACE} -l app=mempalace" "New pod created"

section_header "Query After Restart"

echo -e "${CYAN}# Can we still find the Redis incident?${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/search \
    -d '{"query": "Redis timeout solution"}'

  ✓ FOUND: "Redis timeout - connection pool fix"
  ✓ FOUND: "Database connection exhaustion pattern"
  ✓ FOUND: "Connection pool tuning guide"

  ALL KNOWLEDGE INTACT!

  Why? ChromaDB stores embeddings on PersistentVolume.
  Pod crashes don't lose institutional memory.

EOF
demo_wait 10

show_result "success" "Knowledge persisted through pod crash!"

###############################################################################
# ACT 5: STORE THE NEW INCIDENT
###############################################################################
act "5" "Store This Incident for Next Time"

section_header "Auto-Save to MemPalace"

echo -e "${CYAN}# Store incident report:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/store -d '{
    "content": "Redis connection timeout in payment-api.
                Error: connection pool exhausted.
                Root cause: REDIS_MAX_CONNECTIONS set to 10.
                Solution: Increased to 50 based on past incident.
                Time to resolve: 5 minutes (found in MemPalace).
                No escalation needed.",
    "tags": ["redis", "timeout", "connection-pool",
             "payment-api", "resolved", "2026-07"]
  }'

  ✓ Incident stored with embeddings
  ✓ Tagged for future search
  ✓ Linked to related incidents
  ✓ Available to next on-call engineer

EOF
demo_wait 10

show_result "success" "Institutional memory grows with each incident"

section_header "Knowledge Graph View"

cat << 'EOF'

  Relationship Mining:

  Redis Timeouts ──┬── Connection Pool Issues
                   ├── Performance Tuning
                   └── High Traffic Scaling

  Related Incidents: 4 (including today)
  Team Members Who Solved: 3 engineers
  Average Resolution Time: 8 minutes (with MemPalace)
  Previous Average: 45 minutes (without MemPalace)

  Knowledge compounds over time.

EOF
demo_wait 10

###############################################################################
# ACT 6: THE BIGGER PICTURE
###############################################################################
act "6" "The Bigger Picture"

section_header "Before vs After MemPalace"

cat << 'EOF'

┌─────────────────────────┬────────────────┬──────────────────┐
│ Scenario                │ Without        │ With MemPalace   │
├─────────────────────────┼────────────────┼──────────────────┤
│ 3am Redis timeout       │ Wake senior    │ Search, fix      │
│ Knowledge location      │ People's heads │ Searchable DB    │
│ New engineer onboard    │ Ask everyone   │ Query history    │
│ Senior engineer leaves  │ Knowledge lost │ Knowledge stays  │
│ Time to resolution      │ 45 minutes     │ 5 minutes        │
│ Escalations required    │ Yes            │ No               │
└─────────────────────────┴────────────────┴──────────────────┘

EOF
demo_wait 12

section_header "Real-World Use Cases"

echo -e "${CYAN}# Production incident knowledge bases:${NC}"
bullet "Database performance issues (PostgreSQL, Redis, MongoDB)"
bullet "Network connectivity problems (timeouts, DNS, certificates)"
bullet "Deployment failures (image pull, resource limits, RBAC)"
bullet "Security incidents (CVEs, misconfigurations, breaches)"
bullet "Customer support patterns (common issues, solutions)"
echo ""
demo_wait 8

section_header "ROI Metrics"

echo -e "${WHITE}MemPalace Impact:${NC}"
echo ""
bullet "83% reduction in escalations (junior engineers self-serve)"
bullet "89% faster incident resolution (5min vs 45min average)"
bullet "Zero knowledge loss when engineers leave"
bullet "Semantic search finds solutions keyword search misses"
bullet "Knowledge compounds - 100 incidents = 100 solutions"
echo ""
demo_wait 8

###############################################################################
# ACT 7: SUMMARY
###############################################################################
act "7" "Summary"

section_header "What We Demonstrated"

echo -e "${WHITE}Key Takeaways:${NC}"
echo ""
bullet "Institutional memory persists on PersistentVolume"
bullet "Semantic search finds solutions by meaning, not keywords"
bullet "Junior engineers solve incidents without escalation"
bullet "Knowledge survives pod crashes and team turnover"
bullet "Each incident makes the team smarter"
echo ""
demo_wait 8

section_header "Architecture"

cat << 'EOF'

  ┌────────────────────────────────────────────────┐
  │ OpenShift Pod (ephemeral)                      │
  │  ┌──────────────────────────────────────┐      │
  │  │ MemPalace MCP Server                 │      │
  │  │  - FastAPI + WebSocket               │      │
  │  │  - 29 MCP tools                      │      │
  │  │  - Semantic search API               │      │
  │  └──────────────────────────────────────┘      │
  │         ↓ mounts                               │
  │  ┌──────────────────────────────────────┐      │
  │  │ PersistentVolume (durable)           │      │
  │  │  - ChromaDB vector database          │      │
  │  │  - Embeddings + metadata             │      │
  │  │  - Incident knowledge base           │      │
  │  └──────────────────────────────────────┘      │
  └────────────────────────────────────────────────┘

EOF
demo_wait 10

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
║  Never lose an incident solution again                           ║
║  Deploy: github.com/aicatalyst-team/mempalace-openshift          ║
║  Contact: gtrotman@redhat.com                                     ║
║                                                                   ║
║  MemPalace: Institutional memory that never forgets 🧠           ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF
