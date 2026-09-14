#!/usr/bin/env python3
"""Seed MemPalace with on-narrative content for the round-trip demo."""
import os, agent as a
tok=a.get_token()
a.mcp('initialize',{'protocolVersion':'2025-03-26','capabilities':{},'clientInfo':{'name':'seed','version':'1'}},tok)
try: a.mcp('notifications/initialized',{},tok,notif=True)
except Exception: pass
DR=[('aramco-mcp','auth','OIDC on the Aramco MCP gateway is enforced by an Envoy jwt_authn edge that validates RHBK-issued JWTs against the mcp realm JWKS. Missing or invalid tokens get HTTP 401; valid tokens reach the Kuadrant MCP federation gateway.'),
 ('aramco-mcp','storage','MemPalace deployed via the MCP Lifecycle Operator uses EmptyDir storage. The MCPServer CRD has no PVC source through v0.3.0, so durable storage requires a StatefulSet with a PVC outside the operator.'),
 ('aramco-mcp','architecture','The MCP gateway federates tools from backend MCP servers. ext_proc rewrites the authority header to route tools/call directly to the backend, while initialize and tools/list go to the broker.'),
 ('aramco-mcp','security','A NetworkPolicy restricts the MemPalace backend so only the mcp-gateway-system namespace can reach port 8000, ensuring the gateway cannot be bypassed at the network layer.')]
for w,r,c in DR:
    a.mcp('tools/call',{'name':'mempalace_add_drawer','arguments':{'wing':w,'room':r,'content':c}},tok)
    print('filed',w,'/',r)
