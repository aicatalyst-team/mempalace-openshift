# Narration Script: MCP Server Lifecycle on OpenShift AI

**Duration:** ~8 minutes  
**Presenter:** Gerald Trotman  
**Recording:** QuickTime/OBS with live narration  
**Run command:** `STEP_MODE=1 ./mcp-gateway-lifecycle-demo.sh`

---

## INTRO (0:00 - 0:30)

**[Title card appears]**

> "Every AI agent needs tools. MCP — Model Context Protocol — is how they get them."

**[Pause 2 seconds]**

> "But getting an MCP server from 'works on my laptop' to 'production on OpenShift' — that's the gap this demo closes."

**[Pause 2 seconds]**

**[Bullet list: What we'll show]**

> "Four things: deploy via CRD, federate via gateway, full data round-trip, and MemPalace as the reference implementation."

**[ENTER to advance]**

---

## ACT 1: The Platform (0:30 - 1:30)

**[Act 1 header appears]**

> "First, let's see what we're working with."

**[Pause 2 seconds]**

**[Cluster info displays — oc whoami, oc version]**

> "Authenticated to our OpenShift AI cluster."

**[MCP operators display]**

> "Two operators power the MCP lifecycle. The Lifecycle Operator from kubernetes-sigs deploys servers and runs protocol handshakes. The Gateway Operator from Kuadrant handles broker, router, and tool federation."

**[ENTER to advance through each section]**

---

## ACT 2: Deploy an MCP Server (1:30 - 3:00)

**[Act 2 header appears]**

> "MemPalace is an AI memory system — 29 MCP tools for storing and searching knowledge. It runs on ChromaDB with semantic search. Let's see how it's deployed."

**[MCPServer status displays]**

> "One YAML — an MCPServer custom resource — and the operator did the rest. Pulled the image, created the deployment, ran the protocol handshake, discovered all 29 tools."

**[Pod info displays]**

**[MCP handshake code and result display]**

> "The operator verified this during deployment. We're seeing it ourselves — the server responds with its name, version, and protocol version."

**[Success message: handshake confirmed]**

**[ENTER to advance]**

---

## ACT 3: Federate via MCP Gateway (3:00 - 4:30)

**[Act 3 header appears]**

> "A single MCP server is useful. But production needs a gateway — one endpoint that federates tools from many servers, with routing and access control."

**[Gateway components display]**

> "Four components: Envoy proxy for TLS and load balancing, the MCP Broker for protocol parsing and tool registry, the Router for ext_proc header injection, and the Controller that watches MCPServerRegistration CRDs."

**[Server registration displays]**

> "The registration tells the gateway which HTTPRoute routes to this backend, what path the MCP endpoint lives at, and categories for tool discovery."

**[Broker status JSON displays]**

> "29 tools federated, server healthy, zero conflicts."

**[ENTER to advance]**

---

## ACT 4: End-to-End Data Flow (4:30 - 6:00)

**[Act 4 header appears]**

> "Now the real test — can a client connect through the gateway, store knowledge in MemPalace, and search it back with semantic similarity?"

### Step 1: Initialize Session

**[Initialize curl and response display]**

> "Client connects to the gateway's external address. Gets back a JWT session token."

### Step 2: Discover Available Tools

**[Discover tools response displays]**

> "The gateway returns all federated tools. 29 from MemPalace, organized by category."

### Step 3: Check Palace Status

**[Palace status displays]**

> "Palace is responding through the gateway. We can see the path, drawer count, wings, and rooms."

### Step 4: Store Knowledge

> "Let's add some knowledge about our architecture."

**[Add drawer response displays]**

> "Knowledge stored in ChromaDB — through the MCP Gateway, to the MemPalace backend."

### Step 5: Semantic Search

> "Now search with a natural language query — ChromaDB handles the embedding."

**[Search results display with similarity scores]**

> "Full round trip. The query 'How do I deploy MCP servers to production?' matched our stored knowledge with high similarity."

**[ENTER to advance]**

---

## ACT 5: Under the Hood — Routing Architecture (6:00 - 6:45)

**[Act 5 header appears]**

> "The gateway uses a split routing architecture. This is key to understanding how tools/call reaches the backend."

**[ASCII flow diagram displays]**

**[Pause 4 seconds for reading]**

> "Key insight: tools/call goes DIRECTLY to the backend via Envoy — not through the broker. The ext_proc rewrites the authority header. HTTPRoute hostnames are routing markers, not actual DNS names."

**[Envoy access log displays]**

> "There's the proof — requests routed to mempalace-backend, the routing marker."

**[ENTER to advance]**

---

## ACT 6: Production Considerations (6:45 - 7:15)

**[Act 6 header appears]**

**[Component stack displays]**

> "OpenShift AI 3.4.2, both MCP operators, MemPalace UBI 9 image with ChromaDB. EmptyDir for the PoC — PVC required for production persistence."

**[Multi-server scaling pattern displays]**

> "To add more MCP servers: one CRD, one HTTPRoute, one registration. The gateway federates them all under one endpoint."

**[Security model displays]**

> "Session JWTs, gateway RBAC via MCPServerRegistration, namespace isolation via ReferenceGrants, UBI 9 base images for FIPS and CVE scanning."

**[ENTER to advance]**

---

## ACT 7: Spec Alignment — MCP 2026-07-28 (7:15 - 8:00)

**[Act 7 header appears]**

> "Three weeks ago, the MCP specification released its biggest update yet. Here's why what we just deployed is already aligned with where the protocol is heading."

**[Stateful → Stateless comparison displays]**

> "The big shift: initialize handshake is retired. Session IDs are retired. Every request is now self-contained. Any request can land on any instance behind a round-robin load balancer."

**[Header-based routing section displays]**

> "New headers — Mcp-Method, Mcp-Name — let gateways route on headers alone. No body inspection needed. This is exactly what our ext_proc already does."

**[Architecture mapping table displays]**

> "Look at the mapping. What we deployed today maps directly to where the spec is going."

**[Industry validation displays]**

> "The same gateway pattern is now in production at Microsoft, AWS, Cloudflare, and others. Our architecture is validated."

**[ENTER to advance]**

---

## ACT 8: Summary (8:00 - 8:30)

**[Summary checklist displays]**

> "Seven things demonstrated: operator deployment, protocol handshake, gateway federation, knowledge storage, semantic search, routing verification, and spec alignment."

**[Pattern flow displays]**

> "The pattern: local MCP server, UBI 9 container, MCPServer CRD, gateway federation. From laptop to production."

**[End card displays — hold for 5 seconds]**

> "Thanks for watching."

---

## Timing Notes

**Total spoken time:** ~3 minutes  
**Total demo runtime:** ~8 minutes  
**Silence/demo ratio:** 62% watching, 38% narration

**Key pauses:**
- After architecture diagrams: 4-5 seconds
- After comparison tables: 4 seconds
- Act transitions: 3 seconds
- Let curl responses and JSON output speak for themselves

**Tone guidance:**
- Emphasize "one YAML," "operator did the rest," "29 tools automatically"
- Pause before search results reveal (the similarity score is the payoff)
- Contrast "single server" vs "federated gateway" — the scaling story
- Let the spec alignment table land — don't rush through it
- "Same pattern as Microsoft, AWS, Cloudflare" is the authority anchor
