# Narration Script: MemPalace Demo 2 - Customer Context Engine

**Duration:** ~6 minutes  
**Presenter:** Gerald Trotman  
**Recording:** QuickTime with live narration

---

## INTRO (0:00 - 0:15)

**[Title card appears]**

> "Hi, I'm Gerald Trotman from Red Hat's AI Catalyst Platform Team. A customer emails: My deployment still isn't working. Which deployment? What issue? The customer is frustrated because they already explained this yesterday."

**[Pause 3 seconds]**

> "Let me show you how MemPalace prevents customers from repeating themselves."

**[Pause 2 seconds]**

---

## ACT 1: The Problem - No Context (0:15 - 1:15)

**[Act 1 header appears]**

**[Pause 5 seconds]**

> "Support agents lose context between sessions. And customers hate repeating themselves."

**[Pause 3 seconds]**

**[Day 1 customer email displays]**

**[Pause 10 seconds for reading the email]**

> "Day one. A customer from Acme Corp emails about GPU quota issues on OpenShift four point one four. They're deploying vLLM workloads and hitting limits. They've already tried increasing resource limits in their deployment YAML, but it still fails."

**[Pause 5 seconds]**

> "Agent one, Alex, spends twenty minutes understanding the context. What OpenShift version - customer already said four point one four. What workload - customer already said vLLM. What did you try - customer already said increased limits."

**[Pause 5 seconds]**

> "Alex suggests checking ResourceQuota objects. Session ends."

**[Pause 3 seconds]**

**[Day 2 email displays]**

**[Pause 8 seconds for reading]**

> "Day two. The customer follows up. But agent two, Jordan, is handling the ticket now. Different agent, new session. Jordan reads the email with zero context from yesterday."

**[Pause 4 seconds]**

> "Jordan asks: What OpenShift version are you on? What are you trying to deploy? What have you tried so far?"

**[Pause 4 seconds]**

> "The customer is frustrated: I already explained this yesterday!"

**[Pause 3 seconds]**

> "The problem - agent two has zero context from agent one's session. Terrible customer experience."

**[Pause 3 seconds]**

---

## ACT 2: Day 1 with MemPalace (1:15 - 2:15)

**[Act 2 header appears]**

**[Pause 5 seconds]**

> "Let's replay this scenario with MemPalace capturing customer context."

**[Pause 3 seconds]**

**[Store context command displays]**

**[Pause 8 seconds for reading the payload]**

> "Agent one stores the customer context to MemPalace. Acme Corp from sarah at acmecorp dot com. GPU quota issues on OpenShift four point one four. Deploying vLLM workloads on a cluster with eight A one hundred GPUs. Already tried increasing resource limits. All tagged for future retrieval."

**[Pause 5 seconds]**

**[Store solutions command displays]**

**[Pause 7 seconds for reading]**

> "Agent one also stores the attempted solutions. Suggested checking ResourceQuota objects. Need to verify hard versus soft limits and quota scopes. Tagged as troubleshooting in progress."

**[Pause 4 seconds]**

> "Day one context captured. The customer's issue plus the attempted solutions."

**[Pause 3 seconds]**

**[Tag display shows]**

**[Pause 8 seconds for reading tag list]**

> "MemPalace now knows who - Acme Corp. What - GPU quota error. Where - vLLM deployment on eight A one hundred GPUs. What they tried - increased resource limits, didn't work. And what's next - check ResourceQuota objects."

**[Pause 5 seconds]**

---

## ACT 3: Day 2 - Seamless Handoff (2:15 - 3:30)

**[Act 3 header appears]**

**[Pause 5 seconds]**

> "Next day. Different agent. But this time, MemPalace has the context."

**[Pause 3 seconds]**

**[Search query displays]**

**[Pause 3 seconds]**

> "Agent two, Jordan, receives the follow-up email. Instead of asking the customer to repeat everything, Jordan queries MemPalace."

**[Pause 3 seconds]**

**[Search results display]**

**[Pause 12 seconds for reading both results]**

> "Semantic search returns all the context from day one. The Acme Corp GPU quota issue with full details - deploying vLLM, eight A one hundred GPUs, already tried increasing resource limits. And the troubleshooting steps from agent one - check ResourceQuota objects, verify hard versus soft limits."

**[Pause 5 seconds]**

> "All context from day one retrieved in one query. Agent two has full context without asking the customer anything."

**[Pause 4 seconds]**

**[Agent response email displays]**

**[Pause 12 seconds for reading the response]**

> "Agent two emails the customer: Hi Sarah, I see you're working on GPU quotas for vLLM deployments on your OpenShift four point one four cluster with eight A one hundred GPUs. You've already tried increasing the resource limits, and yesterday we suggested checking ResourceQuota objects. Let me check the actual quota settings in your namespace."

**[Pause 6 seconds]**

> "The customer's reaction: Oh wow, you already know!"

**[Pause 3 seconds]**

> "No repeated questions. No frustration. Seamless handoff between agents."

**[Pause 3 seconds]**

---

## ACT 4: Knowledge Graph Mining (3:30 - 4:30)

**[Act 4 header appears]**

**[Pause 5 seconds]**

> "MemPalace can find patterns across customers using knowledge graphs."

**[Pause 3 seconds]**

**[Graph build results display]**

**[Pause 10 seconds for reading entities and relationships]**

> "Mining relationships from customer interactions, MemPalace extracted six entities: Acme Corp, OpenShift four point one four, vLLM, A one hundred GPU, ResourceQuota, and GPU quota. It discovered six relationships showing how everything connects. Acme Corp uses OpenShift, deploys vLLM, which requires A one hundred GPUs, which are limited by GPU quotas, which are controlled by ResourceQuota objects."

**[Pause 6 seconds]**

**[Related customer search displays]**

**[Pause 10 seconds for reading other customers]**

> "Now we can ask: Do other customers have GPU plus vLLM issues? MemPalace found two. TechStart Inc had the same problem - resolved by creating separate ResourceQuota per namespace in two days. DataFlow LLC had GPU allocation issues with model serving - resolved by adjusting cluster-wide quotas in one day."

**[Pause 6 seconds]**

> "Pattern detected across three customers: vLLM workloads commonly hit GPU quotas. Recommended fix: namespace-scoped ResourceQuota objects."

**[Pause 4 seconds]**

> "Knowledge graphs found the pattern so you don't have to."

**[Pause 3 seconds]**

---

## ACT 5: Tag-Based Organization (4:30 - 5:30)

**[Act 5 header appears]**

**[Pause 5 seconds]**

> "Tags enable powerful customer segmentation and filtering."

**[Pause 3 seconds]**

**[Customer tag taxonomy displays]**

**[Pause 10 seconds for reading all tag categories]**

> "All customers in MemPalace organized by status: twelve with active issues, forty-seven resolved, three escalated. By technology: eight customers with GPU quota problems including Acme Corp, fifteen using vLLM, twenty-three on OpenShift four point one four, six with A one hundred GPUs."

**[Pause 5 seconds]**

**[Inconsistent tagging problem displays]**

**[Pause 5 seconds for reading]**

> "But there's a problem. Inconsistent tagging. Some customers tagged GPU quota, others GPU limits, nvidia quota, GPU resources. They all mean the same thing."

**[Pause 4 seconds]**

**[Tag merge solution displays]**

**[Pause 6 seconds for reading]**

> "Solution: merge the tags. Four inconsistent tags become one. Now fifteen customers are consistently tagged GPU quota instead of eight scattered across four different tags."

**[Pause 4 seconds]**

**[Export report displays]**

**[Pause 12 seconds for reading the report]**

> "Now we can generate a report for all GPU quota customers. Fifteen total customers. Three active issues, twelve resolved. Average resolution time one point eight days. Sixty-seven percent involve vLLM workloads. Common patterns and top solutions, all generated from MemPalace semantic memory."

**[Pause 5 seconds]**

> "Tag-based reporting shows customer patterns at scale."

**[Pause 3 seconds]**

---

## ACT 6: The Bigger Picture (5:30 - 6:30)

**[Act 6 header appears]**

**[Pause 5 seconds]**

**[Comparison table displays]**

**[Pause 10 seconds for reading]**

> "Let's compare the support experience. Without MemPalace: customer context is lost between sessions, agent handoffs force customers to repeat everything, finding similar issues requires manual search through fragmented docs, knowledge organization is inconsistent and scattered, and customers are frustrated saying I already said that."

**[Pause 6 seconds]**

> "With MemPalace: context persists across all sessions, agent handoffs are seamless with full context, similar issues are found automatically through graph mining, knowledge organization is tag-based with merge and export capabilities, and customers say: You already know!"

**[Pause 5 seconds]**

**[MCP tools list displays]**

**[Pause 8 seconds for reading]**

> "This demonstration showed six of the twenty-nine MCP tools in action. Store for customer context. Search for semantic retrieval. Tag add for organization. Tag merge for consolidation. Graph build for relationship mining. And export for reports and analytics."

**[Pause 5 seconds]**

**[Use cases display]**

**[Pause 7 seconds for reading]**

> "Real-world use cases for customer context engines. Technical support to remember customer history. Sales to track prospect interactions across the team. Account management for customer relationship context. Healthcare for patient interaction history. Legal for case context across consultations."

**[Pause 5 seconds]**

**[ROI metrics display]**

**[Pause 8 seconds for reading]**

> "The return on investment is clear. Ninety-two percent reduction in customers having to repeat themselves. Sixty-five percent faster resolution because agents have full context. Seventy-eight percent higher customer satisfaction scores. Forty percent reduction in escalations because context enables self-serve. Zero knowledge loss during agent turnover."

**[Pause 5 seconds]**

---

## ACT 7: Summary (6:30 - 7:00)

**[Act 7 header appears]**

**[Pause 5 seconds]**

**[Key takeaways display]**

**[Pause 7 seconds for reading]**

> "What we demonstrated today. Customer context persists across agent sessions. Semantic search finds relevant history instantly. Knowledge graphs discover patterns across customers. Tag-based organization scales to thousands of customers. And customers never have to repeat themselves."

**[Pause 5 seconds]**

**[Architecture diagram displays]**

**[Pause 9 seconds for reading]**

> "The architecture shows the workflow. Agent one stores context via MCP WebSocket. Agent two searches via MCP WebSocket. Both connect to MemPalace MCP server with twenty-nine tools, semantic embeddings, and knowledge graph mining. Everything persists in ChromaDB on a PersistentVolume - customer context, interaction history, and solution patterns."

**[Pause 5 seconds]**

**[Resources display]**

**[Pause 4 seconds]**

> "Learn more at the Red Hat Developer blog, deploy from GitHub, and check out the Model Context Protocol specification."

**[Pause 3 seconds]**

**[Closing slide displays]**

**[Pause 3 seconds]**

> "Your customers will thank you for never asking them to repeat themselves. Thank you."

**[Pause 3 seconds]**

---

## Recording Notes

**Tone:** Empathetic (everyone hates repeating themselves), customer-focused, relief when context is preserved

**Key Emphasis:**
- "I already explained this yesterday!" (paint customer frustration)
- "You already know!" (the wow moment)
- "Sixty-five percent faster resolution" (ROI)
- "Customers never repeat themselves" (core value)

**Pacing:** Slower on the email displays and search results - these are dense with information
