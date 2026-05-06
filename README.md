# MemPalace on Red Hat OpenShift AI

Deploy [MemPalace](https://github.com/MemPalace/mempalace), a local-first AI memory system, as a production-ready Model Context Protocol (MCP) server on Red Hat OpenShift AI.

**What this provides:**
- HTTP/WebSocket wrapper for MemPalace's MCP protocol (enables Kubernetes deployment)
- UBI 9-based container image with ChromaDB support
- Kubernetes health probes (liveness/readiness)
- OpenShift Security Context Constraint compliance (`restricted-v2`)
- Complete deployment manifests

**Architecture:**
```
┌──────────────────────────────────────────────────────┐
│  MemPalace Pod (UBI 9 Python 3.11)                  │
│                                                      │
│  FastAPI HTTP Server (Port 8000)                    │
│  ├─ GET  /health  → Liveness probe                  │
│  ├─ GET  /ready   → Readiness probe (ChromaDB)      │
│  └─ WS   /mcp     → WebSocket MCP endpoint          │
│                                                      │
│  MCP Server (29 tools: search, mine, query)         │
│  └─ ChromaDB + Knowledge Graph backend              │
│                                                      │
│  Volume: /opt/app-root/data (20Gi PVC)              │
└──────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Red Hat OpenShift 4.x cluster
- `oc` CLI authenticated to cluster
- 20Gi available storage

### Deploy

```bash
# Clone repository
git clone https://github.com/aicatalyst-team/mempalace-openshift
cd mempalace-openshift

# Deploy to OpenShift
oc apply -k manifests/

# Wait for pod to be ready
oc get pods -n mempalace -w

# Test deployment
oc run test-mempalace --rm -i --image=curlimages/curl -- \
  curl -s http://mempalace.mempalace.svc.cluster.local:8000/health
```

Expected output:
```json
{"status":"healthy","protocol":"mcp-over-websocket"}
```

### Access MemPalace

**From within cluster:**
```
ws://mempalace.mempalace.svc.cluster.local:8000/mcp
```

**From external (if Route is deployed):**
```
wss://mempalace-mempalace.apps.your-cluster.com/mcp
```

## What's Inside

### Manifests

- **`01-namespace.yaml`** - Creates `mempalace` namespace
- **`02-pvc.yaml`** - 20Gi PersistentVolumeClaim for palace storage
- **`03-deployment.yaml`** - MemPalace Deployment with health probes
- **`04-service.yaml`** - ClusterIP Service on port 8000
- **`05-route.yaml`** - (Optional) OpenShift Route with TLS edge termination

### Container Image

Pre-built image: `quay.io/aicatalyst/mempalace:latest`

Built from `Dockerfile.ubi` (UBI 9 Python 3.11) with:
- MemPalace 3.3.3 + HTTP wrapper
- ChromaDB with sqlite3 compatibility fix
- FastAPI + uvicorn + websockets

### HTTP Wrapper

`mcp_http_server.py` - Novel contribution that wraps MemPalace's stdio-based MCP server with HTTP/WebSocket transport.

**Key features:**
- Preserves existing `mempalace-mcp` stdio interface
- Enables Kubernetes deployment with health probes
- Supports concurrent WebSocket clients
- Runs `handle_request()` in thread pool (ChromaDB not async-safe)

## Usage Examples

### Test WebSocket Connection

```bash
cd examples
python3 test-connection.py
```

### Semantic Search

```python
import asyncio
import json
import websockets

async def search():
    uri = "ws://mempalace.mempalace.svc.cluster.local:8000/mcp"
    async with websockets.connect(uri) as ws:
        # Initialize
        await ws.send(json.dumps({
            "jsonrpc": "2.0",
            "method": "initialize",
            "params": {"protocolVersion": "2025-11-25"},
            "id": 1
        }))
        await ws.recv()
        
        # Search
        await ws.send(json.dumps({
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "mempalace_search",
                "arguments": {"query": "authentication"}
            },
            "id": 2
        }))
        result = json.loads(await ws.recv())
        print(result)

asyncio.run(search())
```

## Customization

### Change Storage Size

Edit `manifests/02-pvc.yaml`:
```yaml
resources:
  requests:
    storage: 50Gi  # Increase as needed
```

### Enable External Access

Deploy the Route:
```bash
oc apply -f manifests/05-route.yaml
```

Get external URL:
```bash
oc get route mempalace -n mempalace -o jsonpath='{.spec.host}'
```

### Build Custom Image

```bash
# Build locally
podman build -f Dockerfile.ubi -t quay.io/your-org/mempalace:latest --platform linux/amd64 .

# Push to registry
podman push quay.io/your-org/mempalace:latest

# Update manifest
# Edit manifests/03-deployment.yaml and change image: line
```

## Architecture Details

### Why HTTP/WebSocket?

MemPalace's MCP server traditionally uses stdin/stdout (JSON-RPC 2.0). This works for local CLI but breaks in Kubernetes:

| Aspect | Stdio MCP | HTTP/WebSocket MCP |
|--------|-----------|-------------------|
| Transport | stdin/stdout | WebSocket over HTTP |
| Deployment | Local CLI only | Kubernetes/OpenShift |
| Concurrent clients | Single process | Multiple connections |
| Health checks | Not supported | `/health`, `/ready` |
| Service mesh | Impossible | Full compatibility |

### OpenShift Security

Runs under `restricted-v2` SCC:
- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- All capabilities dropped
- `seccompProfile: RuntimeDefault`

Permissions set via `chgrp -R 0` and `chmod -R g=u` (OpenShift uses arbitrary UID, always GID 0).

### ChromaDB on RHEL 9

UBI 9 ships with sqlite3 3.34.x, but ChromaDB requires >= 3.35.0.

**Solution:** Install `pysqlite3-binary` and override via `sitecustomize.py`:
```python
__import__("pysqlite3")
import sys
sys.modules["sqlite3"] = sys.modules.pop("pysqlite3")
```

This works because Python checks `sys.modules` before filesystem imports.

## Troubleshooting

### Pod in CrashLoopBackOff

Check logs:
```bash
POD=$(oc get pods -n mempalace -l app=mempalace -o jsonpath='{.items[0].metadata.name}')
oc logs $POD -n mempalace
```

Common issues:
- ChromaDB connection failed (check PVC is bound)
- sqlite3 version error (verify Dockerfile has sitecustomize.py)

### ImagePullBackOff

If using private registry:
```bash
oc create secret docker-registry quay-pull \
  --docker-server=quay.io \
  --docker-username=YOUR-USERNAME \
  --docker-password=YOUR-PASSWORD \
  -n mempalace

oc secrets link default quay-pull --for=pull -n mempalace
```

### Health Probe Failures

Check readiness:
```bash
oc run test-ready --rm -i --image=curlimages/curl -- \
  curl -s http://mempalace.mempalace.svc.cluster.local:8000/ready
```

Should return `{"status":"ready"}`. If not, ChromaDB backend is not accessible.

## Development

### Local Testing

```bash
# Install with HTTP server dependencies
cd /path/to/mempalace
pip install -e ".[dev,server]"

# Run HTTP server
mempalace-mcp-http --palace ~/.mempalace --port 8000

# Test
curl http://localhost:8000/health
```

### WebSocket Testing

```bash
cd examples
python3 test-connection.py
```

## Contributing

This repository contains the HTTP/WebSocket wrapper and deployment manifests. The wrapper will be contributed to upstream MemPalace.

**Components:**
- **HTTP wrapper** (`mcp_http_server.py`) - Novel contribution for production Kubernetes deployment
- **UBI 9 Dockerfile** - Enterprise-ready container image
- **OpenShift manifests** - Kustomize-based deployment

## Resources

- **MemPalace GitHub:** https://github.com/MemPalace/mempalace
- **MCP Specification:** https://modelcontextprotocol.io
- **Red Hat OpenShift AI:** https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai
- **Blog Post:** [Deploying MemPalace MCP Server on Red Hat OpenShift AI](TBD)

## License

- **MemPalace:** MIT License
- **HTTP wrapper and deployment manifests:** Apache 2.0 License

---

**Maintained by:** [Red Hat AI Catalyst Team](https://github.com/aicatalyst-team)
