# Narration Script: MemPalace Demo 3 - Team Knowledge Multiplier

**Duration:** ~7 minutes  
**Presenter:** Gerald Trotman  
**Recording:** QuickTime with live narration

---

## INTRO (0:00 - 0:20)

**[Title card appears]**

> "Hi, I'm Gerald Trotman from Red Hat's AI Catalyst Platform Team. Security team: did we check container image CVEs? Platform team: are we using the right storage class? App team: what Python version is standard?"

**[Pause 3 seconds]**

> "Three teams. Three silos. One shared knowledge gap. Let me show you how MemPalace turns knowledge silos into shared intelligence."

**[Pause 2 seconds]**

---

## ACT 1: The Problem - Knowledge Silos (0:20 - 1:15)

**[Act 1 header appears]**

**[Pause 5 seconds]**

> "Teams work in isolation. Knowledge stays in silos."

**[Pause 3 seconds]**

**[Monday morning scenario displays]**

**[Pause 10 seconds for reading the three-team scenario]**

> "Monday morning. Three teams, same project. The security team scans container images and writes the results in a Slack thread. The platform team needs the Python version but doesn't know security already answered this. They ask in a different Slack channel. The app team needs to know the base image but doesn't know security approved UBI 9, and doesn't know platform chose gp3 storage. They search the wiki - outdated."

**[Pause 5 seconds]**

> "Three teams, duplicating research, making inconsistent decisions, with no single source of truth."

**[Pause 3 seconds]**

---

## ACT 2: Security Agent - Scan and Share (1:15 - 2:30)

**[Act 2 header appears]**

**[Pause 5 seconds]**

> "The security agent scans the codebase and shares findings through MemPalace."

**[Pause 3 seconds]**

**[Security agent pod info displays]**

**[Pause 3 seconds]**

**[Security scan store command displays]**

**[Pause 8 seconds for reading the scan payload]**

> "The security agent stores scan results to MemPalace. UBI 9 base image, Python three point eleven point nine, zero critical CVEs, zero high CVEs, two medium in transitive dependencies - both mitigated. Verdict: approved for production deployment. All tagged for future retrieval by any agent."

**[Pause 5 seconds]**

**[Dependency audit command displays]**

**[Pause 7 seconds for reading]**

> "The security agent also stores the dependency audit. Forty-seven direct packages, one hundred twelve transitive. All open source compatible - Apache two, MIT, BSD. ChromaDB, FastAPI, sentence-transformers - all cleared."

**[Pause 4 seconds]**

**[Knowledge graph build displays]**

**[Pause 8 seconds for reading entities and relationships]**

> "The security agent builds a knowledge graph from the scan data. Five entities extracted - UBI 9, Python three point eleven, ChromaDB, FastAPI, and the Clair scanner. Six relationships discovered showing how the stack connects. UBI 9 runs Python three point eleven, which depends on ChromaDB and FastAPI. Clair scanned and approved UBI 9."

**[Pause 5 seconds]**

---

## ACT 3: Platform Agent - Informed Decisions (2:30 - 3:45)

**[Act 3 header appears]**

**[Pause 5 seconds]**

> "Different agent. Different team. But shared knowledge through MemPalace."

**[Pause 3 seconds]**

**[Platform agent pod info displays]**

**[Pause 3 seconds]**

**[Search query and results display]**

**[Pause 8 seconds for reading search results]**

> "The platform agent asks: what Python version is the app using? MemPalace returns the answer instantly. Python three point eleven point nine on UBI 9, production approved. From the security agent's scan two hours ago. Distance zero point zero nine - exact match. No need to re-research. No need to message anyone."

**[Pause 5 seconds]**

**[Storage decision store command displays]**

**[Pause 7 seconds for reading]**

> "The platform agent stores the storage decision. gp3-csi storage class, twenty gigabyte PVC for ChromaDB, ReadWriteOnce access mode, daily VolumeSnapshot backup, GPU node affinity for embedding generation. Cross-referenced with security findings."

**[Pause 4 seconds]**

**[Networking config store displays]**

**[Pause 6 seconds for reading]**

> "Platform agent also stores networking config. ClusterIP service on port eight thousand, edge TLS termination through the OpenShift router, network policy allowing traffic from hermes-agent namespace only."

**[Pause 3 seconds]**

> "Platform decisions documented in MemPalace. No Slack threads to search through later."

**[Pause 3 seconds]**

---

## ACT 4: App Agent - Full Context (3:45 - 5:00)

**[Act 4 header appears]**

**[Pause 5 seconds]**

> "Third agent. Third team. Complete context from MemPalace."

**[Pause 3 seconds]**

**[App agent pod info displays]**

**[Pause 3 seconds]**

**[Search results with cross-team findings display]**

**[Pause 10 seconds for reading all five results]**

> "The app agent asks: what base image and configuration should I use? MemPalace returns results from all teams in one query. From security: UBI 9, Python three point eleven, zero critical CVEs. From security: forty-seven packages audited, all licensed. From platform: gp3-csi storage, twenty gigabyte PVC. From platform: ClusterIP on port eight thousand, edge TLS."

**[Pause 5 seconds]**

> "All context from both teams in one query. The app agent has complete context without a single meeting or Slack message."

**[Pause 4 seconds]**

**[Decision table displays]**

**[Pause 8 seconds for reading the table]**

> "Every decision the app agent makes is traced to its source. Base image UBI 9 - from security scan. Python three point eleven - from security scan. Storage gp3-csi - from platform team. PVC twenty gig - from platform team. Port eight thousand - from platform team. TLS edge - from platform team. Packages forty-seven - from security audit. Zero ambiguity. Every choice traced to its source."

**[Pause 5 seconds]**

**[App deployment store command displays]**

**[Pause 7 seconds for reading]**

> "The app agent stores the deployment record. Image pushed to quay dot io, running on UBI 9 with Python three point eleven, twenty gig gp3-csi PVC, ClusterIP on port eight thousand, all health checks passing. Cross-team decision lineage preserved."

**[Pause 4 seconds]**

---

## ACT 5: Knowledge Survives Pod Crashes (5:00 - 5:45)

**[Act 5 header appears]**

**[Pause 5 seconds]**

> "The critical test. Does shared knowledge survive infrastructure failures?"

**[Pause 3 seconds]**

**[Pod status displays]**

**[Pause 3 seconds]**

> "Let's delete the MemPalace pod. Simulating a crash."

**[Pause 2 seconds]**

**[Delete command executes]**

**[Pause 4 seconds]**

> "Pod terminating. All in-memory state is lost. OpenShift is recreating the pod."

**[Pause 5 seconds during countdown]**

**[New pod status displays]**

**[Pause 3 seconds]**

**[Search results after crash display]**

**[Pause 8 seconds for reading]**

> "All cross-team knowledge is intact. Security scan, dependency audit, platform storage, platform networking, app deployment. Everything survived the pod crash. Why? Because ChromaDB stores on the PersistentVolume. Pod crashes don't lose team knowledge."

**[Pause 4 seconds]**

---

## ACT 6: Cross-Team Knowledge Graph (5:45 - 6:45)

**[Act 6 header appears]**

**[Pause 5 seconds]**

> "MemPalace shows how decisions connect across teams."

**[Pause 3 seconds]**

**[Cross-team knowledge graph displays]**

**[Pause 10 seconds for reading the graph]**

> "The cross-team knowledge graph shows the full decision lineage. Security approved UBI 9 and Python three point eleven. Platform specified gp3-csi storage and ClusterIP networking. App deployed the final image with all of those decisions baked in. Every app choice traces back to a security approval or platform specification."

**[Pause 5 seconds]**

**[Compliance report displays]**

**[Pause 10 seconds for reading the report]**

> "And from all that shared knowledge, MemPalace auto-generates a compliance report. Security section: zero critical CVEs, UBI 9 supported, all dependencies licensed. Platform section: gp3-csi with daily snapshots, edge TLS, namespace-scoped network policy. Application section: production image, health probes passing. Decision audit trail: three teams contributed, seven decisions documented, zero conflicts detected."

**[Pause 5 seconds]**

> "A compliance report that used to take days of cross-team coordination, generated in seconds from MemPalace semantic memory."

**[Pause 3 seconds]**

---

## ACT 7: The Bigger Picture (6:45 - 7:30)

**[Act 7 header appears]**

**[Pause 5 seconds]**

**[Comparison table displays]**

**[Pause 10 seconds for reading]**

> "Let's compare. Without MemPalace: knowledge shared in Slack threads lost in scroll, cross-team context requires asking someone and hoping they reply, no decision lineage, three teams scanning the same things, compliance reports manually gathered from each team. Knowledge lost when people leave."

**[Pause 5 seconds]**

> "With MemPalace: semantic memory always findable, cross-team queries return instant results, full audit trail with attribution, scan once and share to all, compliance reports auto-generated, and knowledge survives pod crashes and team member transitions."

**[Pause 5 seconds]**

**[MCP tools list displays]**

**[Pause 5 seconds for reading]**

> "This demonstration showed five of the twenty-nine MCP tools. Store for contributing knowledge. Search for querying across teams. Graph build for visualizing cross-team relationships. Export for compliance reports. And tag add for organizing by team, domain, and quarter."

**[Pause 4 seconds]**

**[Use cases display]**

**[Pause 5 seconds for reading]**

> "Real-world use cases: DevSecOps alignment across security, platform, and app teams. Compliance with full decision audit trails. Onboarding where new team members query institutional knowledge. Incident response with cross-team context. And architecture decision records with full context."

**[Pause 4 seconds]**

**[ROI metrics display]**

**[Pause 6 seconds for reading]**

> "The return on investment. Seventy percent reduction in duplicated research across teams. Eighty-five percent faster cross-team decisions. One hundred percent decision audit trail. Zero knowledge loss during team transitions. And compliance reports generated in seconds instead of days."

**[Pause 4 seconds]**

---

## ACT 8: Summary (7:30 - 8:00)

**[Act 8 header appears]**

**[Pause 5 seconds]**

**[Key takeaways display]**

**[Pause 5 seconds for reading]**

> "What we demonstrated today. Three agent pods sharing knowledge through one MemPalace. Security findings instantly available to platform and app teams. Platform decisions inform app deployment without meetings. Knowledge graph shows decision lineage across teams. Shared knowledge survives pod crashes. And compliance reports auto-generated from semantic memory."

**[Pause 5 seconds]**

**[Architecture diagram displays]**

**[Pause 8 seconds for reading]**

> "The architecture is straightforward. Three agents - security, platform, and app - each connect to the same MemPalace MCP server via WebSocket. MemPalace provides twenty-nine tools for storing, searching, graphing, and exporting knowledge. ChromaDB on a PersistentVolume stores security scans, platform decisions, app deployments, and the decision lineage graph."

**[Pause 5 seconds]**

**[Resources display]**

**[Pause 4 seconds]**

> "Learn more at the Red Hat Developer blog, deploy from GitHub, and check out the Model Context Protocol specification."

**[Pause 3 seconds]**

**[Closing slide displays]**

**[Pause 3 seconds]**

> "Stop duplicating work. Start multiplying knowledge. Thank you."

**[Pause 3 seconds]**

---

## Recording Notes

**Tone:** Collaborative, practical, "we've all been there" energy. Build from frustration (silos) to relief (shared knowledge).

**Key Emphasis:**
- "Three teams, three silos" (paint the pain)
- "All context from both teams in one query" (the wow moment)
- "Every choice traced to its source" (governance/compliance angle)
- "Zero knowledge loss" (institutional resilience)

**Pacing:** Slower on the cross-team search results and the compliance report - these are the payoff moments. Let the decision table breathe so viewers can read each row.
