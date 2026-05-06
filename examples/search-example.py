#!/usr/bin/env python3
"""
Semantic search example using MemPalace MCP server.

This demonstrates how to:
1. Connect to MemPalace via WebSocket
2. Initialize an MCP session
3. Store a memory
4. Search for related memories

Usage:
    # From within cluster:
    python3 search-example.py ws://mempalace.mempalace.svc.cluster.local:8000/mcp

    # From external (if Route is deployed):
    python3 search-example.py wss://mempalace-mempalace.apps.your-cluster.com/mcp
"""

import asyncio
import json
import sys
import websockets


async def search_demo(uri):
    """Demonstrate semantic search capabilities."""
    print(f"Connecting to {uri}...")

    async with websockets.connect(uri) as ws:
        # Initialize session
        await ws.send(json.dumps({
            "jsonrpc": "2.0",
            "method": "initialize",
            "params": {"protocolVersion": "2025-11-25"},
            "id": 1
        }))
        init_response = json.loads(await ws.recv())
        print(f"✓ Session initialized: {init_response['result']['serverInfo']['name']}")

        # Store a sample memory
        print("\nStoring sample memory about authentication...")
        await ws.send(json.dumps({
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "mempalace_create_memory",
                "arguments": {
                    "content": "Implemented OAuth 2.0 authentication with JWT tokens. "
                               "Tokens expire after 1 hour. Refresh tokens valid for 30 days. "
                               "Using RS256 algorithm with rotating keys.",
                    "tags": ["authentication", "security", "oauth2", "jwt"]
                }
            },
            "id": 2
        }))

        create_response = json.loads(await ws.recv())
        if "result" in create_response:
            print("✓ Memory stored successfully")

        # Search for related memories
        print("\nSearching for 'token expiration'...")
        await ws.send(json.dumps({
            "jsonrpc": "2.0",
            "method": "tools/call",
            "params": {
                "name": "mempalace_search",
                "arguments": {
                    "query": "token expiration",
                    "limit": 5
                }
            },
            "id": 3
        }))

        search_response = json.loads(await ws.recv())

        if "result" in search_response:
            results = json.loads(search_response["result"]["content"][0]["text"])
            print(f"\n✓ Found {len(results)} relevant memories:")
            for idx, result in enumerate(results, 1):
                print(f"\n  {idx}. Score: {result.get('distance', 'N/A')}")
                print(f"     Content: {result['content'][:100]}...")
                if result.get('tags'):
                    print(f"     Tags: {', '.join(result['tags'])}")

        print("\n✓ Search demo complete!")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 search-example.py <websocket-uri>")
        print("Example: python3 search-example.py ws://mempalace.mempalace.svc.cluster.local:8000/mcp")
        sys.exit(1)

    uri = sys.argv[1]
    asyncio.run(search_demo(uri))
