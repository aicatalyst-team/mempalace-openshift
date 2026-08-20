# Narration Script: MemPalace Demo 1 - Incident Knowledge Base

**Duration:** ~5 minutes  
**Presenter:** Gerald Trotman  
**Recording:** QuickTime with live narration

---

## INTRO (0:00 - 0:15)

**[Title card appears]**

> "Hi, I'm Gerald Trotman from Red Hat's AI Catalyst Platform Team. It's three AM. Your pager goes off. Redis connection timeouts. Do you wake up your senior engineer, or do you search MemPalace?"

**[Pause 3 seconds]**

> "Let me show you how institutional memory prevents middle-of-the-night escalations."

**[Pause 2 seconds]**

---

## ACT 1: The Problem - Lost Knowledge (0:15 - 1:00)

**[Act 1 header appears]**

**[Pause 5 seconds]**

> "Every team has this problem. Tribal knowledge locked in people's heads."

**[Pause 3 seconds]**

**[Typical incident response scenario displays]**

**[Pause 8 seconds for reading the scenario]**

> "A critical alert fires at three AM. Redis connection timeout in the payment API. The junior engineer on-call searches Slack - nothing. Searches JIRA - twelve tickets, none match. Searches the wiki - outdated, last updated two years ago. Finally escalates to the senior engineer and ruins their night."

**[Pause 5 seconds]**

> "The senior engineer, half asleep, says: Oh yeah, we hit this six months ago. Just increase the connection pool size. It's in the ConfigMap."

**[Pause 4 seconds]**

> "The problem? That knowledge was in someone's head, not searchable. The incident took forty-five minutes because the solution wasn't captured."

**[Pause 3 seconds]**

---

## ACT 2: MemPalace Has Institutional Memory (1:00 - 2:15)

**[Act 2 header appears]**

**[Pause 5 seconds]**

> "Let's show how MemPalace prevents this problem."

**[Pause 3 seconds]**

**[MemPalace pod status displays]**

**[Pause 5 seconds]**

> "MemPalace is running on OpenShift. Let's query it for Redis incidents using semantic search."

**[Pause 3 seconds]**

**[Search results display]**

**[Pause 10 seconds for reading the three results]**

> "Semantic search found three related incidents. First, Redis timeout connection pool fix from six months ago. The exact solution we need. Second, database connection exhaustion - a similar pattern. Third, connection pool tuning for high traffic - a related best practice."

**[Pause 5 seconds]**

> "Notice the distance scores. Point one two is very similar. These aren't keyword matches - MemPalace understood that connection pool maps to timeout, that exhaustion maps to errors, that tuning maps to fix. Semantic search finds meaning, not just keywords."

**[Pause 4 seconds]**

> "The junior engineer found the solution in seconds. No senior engineer needed."

**[Pause 3 seconds]**

---

## ACT 3: Apply the Fix (2:15 - 3:00)

**[Act 3 header appears]**

**[Pause 5 seconds]**

> "Now the junior engineer applies the fix from six months ago."

**[Pause 3 seconds]**

**[ConfigMap displays]**

**[Pause 5 seconds for reading config]**

> "The current config shows Redis max connections set to ten. That's too low. Based on the MemPalace solution, we increase it to fifty."

**[Pause 3 seconds]**

**[Patch command executes]**

**[Pause 4 seconds]**

> "ConfigMap updated. Pods restarting with the new configuration."

**[Pause 3 seconds]**

**[Countdown displays]**

**[Pause 4 seconds]**

**[Success message displays]**

**[Pause 5 seconds for reading]**

> "Errors stopped. Connection pool metrics are healthy. Incident resolved in five minutes, not forty-five. And the senior engineer is still sleeping."

**[Pause 4 seconds]**

> "The junior engineer solved it without escalation, thanks to institutional memory."

**[Pause 3 seconds]**

---

## ACT 4: Knowledge Survives Pod Crashes (3:00 - 4:00)

**[Act 4 header appears]**

**[Pause 5 seconds]**

> "Now the critical test. Does knowledge survive infrastructure failures?"

**[Pause 3 seconds]**

**[Pod status displays]**

**[Pause 4 seconds]**

> "Let's simulate a pod crash by deleting the MemPalace pod."

**[Pause 2 seconds]**

**[Delete command executes]**

**[Pause 4 seconds]**

> "Pod terminating. All in-memory state is lost. OpenShift is recreating the pod."

**[Pause 5 seconds during countdown]**

**[New pod status displays]**

**[Pause 4 seconds]**

> "New pod is running. Now the moment of truth - can we still find the Redis incident?"

**[Pause 3 seconds]**

**[Search results display]**

**[Pause 6 seconds for reading]**

> "All knowledge is intact. The Redis timeout solution, the database exhaustion pattern, the connection pool tuning guide - everything is still there."

**[Pause 4 seconds]**

> "Why? Because ChromaDB stores embeddings on the PersistentVolume. Pod crashes don't lose institutional memory."

**[Pause 3 seconds]**

---

## ACT 5: Store This Incident (4:00 - 4:45)

**[Act 5 header appears]**

**[Pause 5 seconds]**

> "Now the junior engineer stores today's incident for the next person."

**[Pause 3 seconds]**

**[Store command and payload display]**

**[Pause 8 seconds for reading the incident report]**

> "The incident report includes the error, the root cause, the solution, and how long it took to resolve. All tagged for future search and linked to related incidents."

**[Pause 5 seconds]**

> "This is how institutional memory grows. Every incident makes the team smarter."

**[Pause 3 seconds]**

**[Knowledge graph displays]**

**[Pause 7 seconds for reading relationships]**

> "The knowledge graph shows Redis timeouts connected to connection pool issues, performance tuning, and high traffic scaling. Four related incidents now, including today's. Three engineers have solved similar problems. Average resolution time dropped from forty-five minutes to eight minutes."

**[Pause 4 seconds]**

> "Knowledge compounds over time."

**[Pause 2 seconds]**

---

## ACT 6: The Bigger Picture (4:45 - 5:30)

**[Act 6 header appears]**

**[Pause 5 seconds]**

**[Before/After comparison table displays]**

**[Pause 8 seconds for reading table]**

> "Let's look at the impact. Before MemPalace: wake the senior engineer, knowledge stuck in people's heads, new engineers ask everyone, when someone leaves knowledge is lost, forty-five minutes to resolve, escalations required."

**[Pause 5 seconds]**

> "With MemPalace: search and fix yourself, knowledge in a searchable database, new engineers query history, when someone leaves knowledge stays, five minutes to resolve, no escalations needed."

**[Pause 4 seconds]**

**[Use cases display]**

**[Pause 6 seconds for reading]**

> "Real-world use cases for production incident knowledge bases. Database performance issues. Network connectivity problems. Deployment failures. Security incidents. Customer support patterns."

**[Pause 4 seconds]**

**[ROI metrics display]**

**[Pause 7 seconds for reading]**

> "The return on investment is clear. Eighty-three percent reduction in escalations because junior engineers can self-serve. Eighty-nine percent faster incident resolution. Zero knowledge loss when engineers leave. Semantic search finds solutions that keyword search misses. And knowledge compounds - one hundred incidents equals one hundred solutions."

**[Pause 4 seconds]**

---

## ACT 7: Summary (5:30 - 6:00)

**[Act 7 header appears]**

**[Pause 5 seconds]**

**[Key takeaways display]**

**[Pause 6 seconds for reading]**

> "What we demonstrated today. Institutional memory persists on PersistentVolume storage. Semantic search finds solutions by meaning, not just keywords. Junior engineers solve incidents without escalation. Knowledge survives pod crashes and team turnover. And each incident makes the team smarter."

**[Pause 5 seconds]**

**[Architecture diagram displays]**

**[Pause 7 seconds for reading]**

> "The architecture is simple. MemPalace MCP server runs in an OpenShift pod. FastAPI with WebSocket, twenty-nine MCP tools, semantic search API. It mounts a PersistentVolume with ChromaDB for vector storage, embeddings with metadata, and your incident knowledge base."

**[Pause 5 seconds]**

**[Resources display]**

**[Pause 4 seconds]**

> "Learn more at the Red Hat Developer blog, deploy from GitHub, and check out the Model Context Protocol specification."

**[Pause 3 seconds]**

**[Closing slide displays]**

**[Pause 3 seconds]**

> "Sleep better knowing your team's knowledge is searchable. Thank you."

**[Pause 3 seconds]**

---

## Recording Notes

**Tone:** Empathetic (everyone knows the 3am page pain), confident, relief-focused

**Key Emphasis:**
- "Three AM" (paint the pain)
- "Forty-five minutes vs five minutes" (dramatic ROI)
- "Knowledge survives" (core value prop)
- "No escalation needed" (sleep better)

**Pacing:** Match pauses to on-screen text density. Let technical displays breathe.
