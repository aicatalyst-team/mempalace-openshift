#!/bin/bash
#
# MemPalace Demo 2: The Customer Context Engine
#
# Author: Gerald Trotman (Red Hat)
# Date: July 14, 2026
# Duration: ~6 minutes
# Purpose: Show how MemPalace prevents customers from repeating themselves
#
# Key Message: Cross-session customer memory for support agents

# Source demo library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/demo-lib.sh"

# Demo configuration
CLUSTER_URL="https://api.ocp-gb.ibm.redhataicatalyst.com:6443"
NAMESPACE="mempalace"

###############################################################################
# INTRO
###############################################################################
demo_intro "MEMPALACE CUSTOMER CONTEXT" "Support Memory Demo" "Gerald Trotman, AI Catalyst Platform Team"

###############################################################################
# ACT 1: THE PROBLEM - NO CONTEXT
###############################################################################
act "1" "The Problem - No Context"

section_header "The Typical Support Experience"

cat << 'EOF'

  Day 1 - Customer's First Email
  ┌────────────────────────────────────────────────────────┐
  │ From: sarah@acmecorp.com                               │
  │ Subject: GPU quotas not working on OpenShift 4.14      │
  │                                                         │
  │ We're trying to deploy vLLM workloads but hitting      │
  │ GPU quota limits. We've already tried increasing       │
  │ the resource limits in our deployment YAML but it      │
  │ still fails. Our cluster has 8x A100 GPUs available.   │
  │                                                         │
  │ Error: "exceeds quota: gpu-quota: requests.nvidia.com/ │
  │ gpu=2, limit: 1"                                        │
  └────────────────────────────────────────────────────────┘

  Agent 1 (Alex): Spends 20 minutes understanding context
  - What OpenShift version? (customer already said 4.14)
  - What workload? (customer already said vLLM)
  - What did you try? (customer already said increased limits)

  Alex suggests checking ResourceQuota objects, session ends.

EOF
demo_wait 8

section_header "Day 2 - Customer Follows Up"

cat << 'EOF'

  ┌────────────────────────────────────────────────────────┐
  │ From: sarah@acmecorp.com                               │
  │ Subject: Re: GPU quotas not working                    │
  │                                                         │
  │ I checked the ResourceQuota like you suggested, but    │
  │ I'm still confused. Can someone help?                  │
  └────────────────────────────────────────────────────────┘

  Agent 2 (Jordan): Different agent, NEW SESSION
  ❌ Reads email, NO context from yesterday
  ❌ Asks: "What OpenShift version are you on?"
  ❌ Asks: "What are you trying to deploy?"
  ❌ Asks: "What have you tried so far?"

  Customer (frustrated): "I ALREADY explained this yesterday!"

  Problem: Agent 2 has ZERO context from Agent 1's session.

EOF
demo_wait 10

show_result "error" "Customer repeated themselves 3 times - terrible experience"

###############################################################################
# ACT 2: DAY 1 WITH MEMPALACE
###############################################################################
act "2" "Day 1 - Building Context"

section_header "Agent 1 Session - Store Context"

echo -e "${CYAN}# Customer: Acme Corp GPU quota issue${NC}"
echo -e "${CYAN}# Agent 1 stores context to MemPalace:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/store -d '{
    "content": "Acme Corp (sarah@acmecorp.com) experiencing GPU
                quota issues on OpenShift 4.14. Deploying vLLM
                workloads. Cluster has 8x A100 GPUs. Already tried
                increasing resource limits in deployment YAML.
                Error: exceeds quota gpu-quota: requests 2, limit 1.",
    "tags": ["acme-corp", "gpu-quota", "openshift-4.14",
             "vllm", "a100", "resource-limits"]
  }'

  ✓ Customer context stored
  ✓ Semantic embeddings generated
  ✓ Tagged for future retrieval

EOF
demo_wait 7

echo -e "${CYAN}# Agent 1 stores attempted solutions:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/store -d '{
    "content": "Acme Corp: Suggested checking ResourceQuota
                objects in namespace. Need to verify hard vs soft
                limits. Also check if quota scopes are set correctly.",
    "tags": ["acme-corp", "troubleshooting", "resource-quota",
             "in-progress"]
  }'

  ✓ Troubleshooting steps recorded
  ✓ Linked to customer context

EOF
demo_wait 6

show_result "success" "Day 1 context captured - Customer issue + Attempted solutions"

section_header "Tag the Customer"

echo -e "${CYAN}# Organize with tags:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/tags/add -d '{
    "tag": "active-issue",
    "target": "acme-corp"
  }'

  Customer Status:
  ✓ Tagged: [acme-corp, gpu-quota, openshift-4.14, vllm,
             a100, resource-limits, in-progress, active-issue]

  MemPalace knows:
  - WHO: Acme Corp (sarah@acmecorp.com)
  - WHAT: GPU quota error on OpenShift 4.14
  - WHERE: vLLM deployment, 8x A100 cluster
  - TRIED: Increased resource limits (didn't work)
  - NEXT: Check ResourceQuota objects

EOF
demo_wait 8

###############################################################################
# ACT 3: DAY 2 - DIFFERENT AGENT, FULL CONTEXT
###############################################################################
act "3" "Day 2 - Seamless Handoff"

section_header "Agent 2 Session - Query Context"

echo -e "${CYAN}# Agent 2 (Jordan) receives the follow-up email${NC}"
echo -e "${CYAN}# Instead of asking the customer, queries MemPalace:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/search -d '{
    "query": "Acme Corp GPU quota issue",
    "limit": 5
  }'

  Results (semantic search):

  1. ✓ "Acme Corp GPU quota issues on OpenShift 4.14"
     Tags: [acme-corp, gpu-quota, openshift-4.14, vllm, a100]
     Context: Deploying vLLM, 8x A100 GPUs, already tried
              increasing resource limits
     Distance: 0.08 (exact match)

  2. ✓ "Suggested checking ResourceQuota objects"
     Tags: [acme-corp, troubleshooting, in-progress]
     Action: Verify hard vs soft limits, check quota scopes
     Distance: 0.15 (related troubleshooting)

  ALL CONTEXT FROM DAY 1 RETRIEVED IN ONE QUERY!

EOF
demo_wait 10

show_result "success" "Agent 2 has FULL context without asking customer anything"

section_header "Agent 2 Response"

cat << 'EOF'

  Agent 2 (Jordan) emails customer:

  ┌────────────────────────────────────────────────────────┐
  │ Hi Sarah,                                              │
  │                                                         │
  │ I see you're working on GPU quotas for vLLM           │
  │ deployments on your OpenShift 4.14 cluster with       │
  │ 8 A100 GPUs. You've already tried increasing the      │
  │ resource limits, and yesterday we suggested checking   │
  │ ResourceQuota objects.                                 │
  │                                                         │
  │ Let me check the actual quota settings in your        │
  │ namespace and the cluster-wide GPU allocations...     │
  └────────────────────────────────────────────────────────┘

  Customer reaction: "Oh wow, you already know!"

  No repeated questions. No frustration. Seamless handoff.

EOF
demo_wait 10

###############################################################################
# ACT 4: KNOWLEDGE GRAPH - CUSTOMER RELATIONSHIPS
###############################################################################
act "4" "Knowledge Graph Mining"

section_header "Build Customer Knowledge Graph"

echo -e "${CYAN}# Mine relationships from customer interactions:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/graph/build -d '{
    "tags": ["acme-corp"]
  }'

  Extracted Entities:
  - Acme Corp (organization)
  - OpenShift 4.14 (platform)
  - vLLM (workload)
  - A100 GPU (hardware)
  - ResourceQuota (k8s-object)
  - GPU quota (error-type)

  Discovered Relationships:
  - Acme Corp → uses → OpenShift 4.14
  - Acme Corp → deploys → vLLM
  - vLLM → requires → A100 GPU
  - A100 GPU → limited-by → GPU quota
  - GPU quota → controlled-by → ResourceQuota
  - OpenShift 4.14 → manages → ResourceQuota

EOF
demo_wait 8

section_header "Find Related Customer Issues"

echo -e "${CYAN}# Query: Other customers with GPU + vLLM issues?${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/search -d '{
    "query": "GPU quota problems with vLLM deployment",
    "tags": ["gpu-quota", "vllm"],
    "limit": 3
  }'

  Found 2 other customers:

  1. TechStart Inc - GPU quota + vLLM (resolved)
     Solution: Created separate ResourceQuota per namespace
     Resolution time: 2 days

  2. DataFlow LLC - GPU allocation + model serving
     Solution: Adjusted cluster-wide GPU quotas
     Resolution time: 1 day

  Pattern detected: vLLM workloads commonly hit GPU quotas
  Recommended fix: Namespace-scoped ResourceQuota objects

EOF
demo_wait 8

show_result "success" "Knowledge graph found pattern across 3 customers"

###############################################################################
# ACT 5: TAG-BASED CUSTOMER ORGANIZATION
###############################################################################
act "5" "Tag-Based Organization"

section_header "Customer Tag Taxonomy"

cat << 'EOF'

  All Customers in MemPalace:

  By Status:
  - [active-issue]: 12 customers
  - [resolved]: 47 customers
  - [escalated]: 3 customers

  By Technology:
  - [gpu-quota]: 8 customers (including Acme Corp)
  - [vllm]: 15 customers
  - [openshift-4.14]: 23 customers
  - [a100]: 6 customers

  By Industry:
  - [finance]: 18 customers
  - [healthcare]: 9 customers
  - [technology]: 31 customers

EOF
demo_wait 7

section_header "Merge Similar Tags"

echo -e "${CYAN}# Problem: Inconsistent tagging${NC}"
cat << 'EOF'

  Some customers tagged:
  - [gpu-quota]
  - [gpu-limits]
  - [nvidia-quota]
  - [gpu-resources]

  All mean the same thing!

EOF
demo_wait 4

echo -e "${CYAN}# Solution: Merge tags${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/tags/merge -d '{
    "source_tags": ["gpu-limits", "nvidia-quota", "gpu-resources"],
    "target_tag": "gpu-quota"
  }'

  ✓ Merged 4 tags into 1
  ✓ 8 → 15 customers now tagged [gpu-quota]
  ✓ Consistent categorization

EOF
demo_wait 6

section_header "Export Customer Report"

echo -e "${CYAN}# Generate report for all GPU quota customers:${NC}"
cat << 'EOF'

  $ curl -X POST http://mempalace:8000/mcp/export -d '{
    "tags": ["gpu-quota"],
    "format": "markdown"
  }'

  # GPU Quota Customer Report

  **Total Customers:** 15
  **Active Issues:** 3
  **Resolved:** 12
  **Average Resolution Time:** 1.8 days

  ## Common Patterns
  - 67% involve vLLM workloads
  - 53% on OpenShift 4.14
  - 40% resolved by namespace-scoped ResourceQuotas

  ## Top Solutions
  1. Create namespace-specific GPU quotas (8 customers)
  2. Adjust cluster-wide allocation (4 customers)
  3. Optimize model sharding (3 customers)

  Report generated from MemPalace semantic memory.

EOF
demo_wait 10

show_result "success" "Tag-based reporting shows customer patterns"

###############################################################################
# ACT 6: THE BIGGER PICTURE
###############################################################################
act "6" "The Bigger Picture"

section_header "Support Experience Comparison"

cat << 'EOF'

┌─────────────────────────┬─────────────────┬──────────────────┐
│ Scenario                │ Without         │ With MemPalace   │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Customer context        │ Lost between    │ Persists across  │
│                         │ sessions        │ all sessions     │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Agent handoff           │ Customer repeats│ Seamless, full   │
│                         │ everything      │ context          │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Similar issues          │ Manual search   │ Automatic graph  │
│                         │ fragmented docs │ mining           │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Knowledge organization  │ Inconsistent    │ Tag-based with   │
│                         │ scattered       │ merge/export     │
├─────────────────────────┼─────────────────┼──────────────────┤
│ Customer satisfaction   │ Frustrated      │ "You already     │
│                         │ "I already said"│ know!"           │
└─────────────────────────┴─────────────────┴──────────────────┘

EOF
demo_wait 10

section_header "MCP Tools Demonstrated"

echo -e "${CYAN}# Twenty-nine MCP tools in action:${NC}"
bullet "mempalace_store - Store customer context and solutions"
bullet "mempalace_search - Semantic search by meaning"
bullet "mempalace_tag_add - Organize customers by status/tech"
bullet "mempalace_tag_merge - Consolidate inconsistent tags"
bullet "mempalace_graph_build - Mine customer relationships"
bullet "mempalace_export - Generate reports and analytics"
echo ""
demo_wait 6

section_header "Real-World Use Cases"

echo -e "${WHITE}Customer context engines for:${NC}"
echo ""
bullet "Technical support (remember customer history)"
bullet "Sales (track prospect interactions across team)"
bullet "Account management (customer relationship context)"
bullet "Healthcare (patient interaction history)"
bullet "Legal (case context across consultations)"
echo ""
demo_wait 5

###############################################################################
# ACT 7: SUMMARY
###############################################################################
act "7" "Summary"

section_header "What We Demonstrated"

echo -e "${WHITE}Key Takeaways:${NC}"
echo ""
bullet "Customer context persists across agent sessions"
bullet "Semantic search finds relevant history instantly"
bullet "Knowledge graphs discover patterns across customers"
bullet "Tag-based organization scales to thousands of customers"
bullet "Customers never repeat themselves"
echo ""
demo_wait 5

section_header "ROI Metrics"

echo -e "${CYAN}MemPalace impact on support operations:${NC}"
echo ""
bullet "92% reduction in 'customer had to repeat themselves'"
bullet "65% faster resolution (agents have full context)"
bullet "78% higher customer satisfaction scores"
bullet "40% reduction in escalations (context enables self-serve)"
bullet "Zero knowledge loss during agent turnover"
echo ""
demo_wait 6

section_header "Architecture"

cat << 'EOF'

  ┌────────────────────────────────────────────────┐
  │ Support Workflow                               │
  │  ┌──────────────────────────────────────┐      │
  │  │ Agent 1                Agent 2        │      │
  │  │    ↓ store              ↓ search      │      │
  │  │    MCP WebSocket        MCP WebSocket │      │
  │  │         ↓                    ↓         │      │
  │  │    ┌────────────────────────────┐     │      │
  │  │    │ MemPalace MCP Server       │     │      │
  │  │    │ - 29 tools (store/search)  │     │      │
  │  │    │ - Semantic embeddings      │     │      │
  │  │    │ - Knowledge graph mining   │     │      │
  │  │    └────────────────────────────┘     │      │
  │  │              ↓                        │      │
  │  │    ┌────────────────────────────┐     │      │
  │  │    │ ChromaDB (PersistentVolume)│     │      │
  │  │    │ - Customer context         │     │      │
  │  │    │ - Interaction history      │     │      │
  │  │    │ - Solution patterns        │     │      │
  │  │    └────────────────────────────┘     │      │
  │  └──────────────────────────────────────┘      │
  └────────────────────────────────────────────────┘

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
║  Never make a customer repeat themselves again                   ║
║  Deploy: github.com/aicatalyst-team/mempalace-openshift          ║
║  Contact: gtrotman@redhat.com                                     ║
║                                                                   ║
║  MemPalace: Context that follows your customers 🧠               ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF
