#!/usr/bin/env python3
"""
Test WebSocket connection to MemPalace MCP server.

Usage:
    # From within cluster:
    python3 test-connection.py ws://mempalace.mempalace.svc.cluster.local:8000/mcp

    # From external (if Route is deployed):
    python3 test-connection.py wss://mempalace-mempalace.apps.your-cluster.com/mcp
"""

import asyncio
import json
import sys
import websockets


async def test_connection(uri):
    """Test MCP server connection and list available tools."""
    print(f"Connecting to {uri}...")

    try:
        async with websockets.connect(uri) as websocket:
            print("✓ WebSocket connection established")

            # Step 1: Initialize MCP session
            init_request = {
                "jsonrpc": "2.0",
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-11-25",
                    "clientInfo": {
                        "name": "mempalace-test-client",
                        "version": "1.0.0"
                    }
                },
                "id": 1
            }

            print("\nSending initialize request...")
            await websocket.send(json.dumps(init_request))

            response = json.loads(await websocket.recv())
            print(f"✓ Initialize response: {json.dumps(response, indent=2)}")

            # Step 2: List available tools
            tools_request = {
                "jsonrpc": "2.0",
                "method": "tools/list",
                "params": {},
                "id": 2
            }

            print("\nListing available tools...")
            await websocket.send(json.dumps(tools_request))

            response = json.loads(await websocket.recv())

            if "result" in response and "tools" in response["result"]:
                tools = response["result"]["tools"]
                print(f"\n✓ Found {len(tools)} tools:")
                for tool in tools[:5]:  # Show first 5
                    print(f"  - {tool['name']}: {tool.get('description', 'No description')}")
                if len(tools) > 5:
                    print(f"  ... and {len(tools) - 5} more")
            else:
                print(f"✗ Unexpected response: {json.dumps(response, indent=2)}")

            print("\n✓ Connection test successful!")

    except websockets.exceptions.WebSocketException as e:
        print(f"✗ WebSocket error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"✗ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 test-connection.py <websocket-uri>")
        print("Example: python3 test-connection.py ws://mempalace.mempalace.svc.cluster.local:8000/mcp")
        sys.exit(1)

    uri = sys.argv[1]
    asyncio.run(test_connection(uri))
