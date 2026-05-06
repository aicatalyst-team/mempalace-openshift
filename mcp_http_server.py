"""
HTTP/WebSocket wrapper for MemPalace MCP Server.

Provides an HTTP transport layer for the JSON-RPC 2.0 MCP protocol,
enabling Kubernetes/OpenShift deployment with health probes.
"""
import asyncio
import json
import logging
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
import uvicorn

# Import existing MCP handler
from .mcp_server import handle_request, _args, _refresh_vector_disabled_flag

logger = logging.getLogger(__name__)

app = FastAPI(
    title="MemPalace MCP Server",
    version="3.3.3",
    description="Model Context Protocol server over WebSocket transport",
)


@app.get("/health")
async def health():
    """
    Liveness probe endpoint for Kubernetes.

    Returns 200 if the server process is running.
    """
    return {"status": "healthy", "protocol": "mcp-over-websocket"}


@app.get("/ready")
async def ready():
    """
    Readiness probe endpoint for Kubernetes.

    Checks if the palace backend is accessible.
    Returns 200 if ready, 503 if not ready.
    """
    try:
        # This refreshes the vector_disabled flag by checking ChromaDB connection
        _refresh_vector_disabled_flag()
        return {"status": "ready"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "error": str(e)}
        )


@app.websocket("/mcp")
async def mcp_websocket(websocket: WebSocket):
    """
    WebSocket endpoint for MCP JSON-RPC 2.0 protocol.

    Accepts WebSocket connections and bridges them to the existing
    stdio-based handle_request() implementation.
    """
    await websocket.accept()
    logger.info("MCP client connected")

    try:
        while True:
            # Receive JSON-RPC request
            message = await websocket.receive_text()

            try:
                request = json.loads(message)
            except json.JSONDecodeError as e:
                logger.error(f"Invalid JSON from client: {e}")
                error_response = {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32700,
                        "message": "Parse error",
                        "data": str(e)
                    },
                    "id": None
                }
                await websocket.send_text(json.dumps(error_response))
                continue

            # Call existing handler (synchronous)
            # Run in thread pool since handle_request() is sync and uses
            # ChromaDB which is not async-safe
            response = await asyncio.to_thread(handle_request, request)

            # Send JSON-RPC response
            if response is not None:
                await websocket.send_text(json.dumps(response))

    except WebSocketDisconnect:
        logger.info("MCP client disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
        try:
            await websocket.close(code=1011, reason=str(e))
        except Exception:
            pass  # Already closed


def main():
    """Entry point for mempalace-mcp-http command."""
    import argparse

    parser = argparse.ArgumentParser(
        description="MemPalace MCP HTTP Server - WebSocket transport for MCP protocol"
    )
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="Bind host (default: 0.0.0.0)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="Bind port (default: 8000)"
    )
    parser.add_argument(
        "--palace",
        help="Palace directory path (default: $MEMPALACE_HOME or ~/.mempalace)"
    )
    parser.add_argument(
        "--log-level",
        default="info",
        choices=["debug", "info", "warning", "error"],
        help="Log level (default: info)"
    )

    args = parser.parse_args()

    # Configure logging
    logging.basicConfig(
        level=args.log_level.upper(),
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    # Update _args for mcp_server module if palace path specified
    if args.palace:
        _args.palace = args.palace

    logger.info(f"Starting MemPalace MCP HTTP server on {args.host}:{args.port}")
    if args.palace:
        logger.info(f"Palace directory: {args.palace}")

    # Run uvicorn server
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        log_level=args.log_level
    )


if __name__ == "__main__":
    main()
