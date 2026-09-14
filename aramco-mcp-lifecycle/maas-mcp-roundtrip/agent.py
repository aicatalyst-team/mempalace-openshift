#!/usr/bin/env python3
"""
MaaS LLM  <->  MCP round-trip agent (full OpenShift AI stack demo).

Flow:
  1. Authenticate to the OIDC-secured MCP edge (RHBK JWT).
  2. MCP initialize + tools/list  -> discover MemPalace tools via the gateway.
  3. Ask the MaaS-hosted Granite LLM (LiteLLM) to solve a task, offering the tools.
     (Tool use is driven by structured JSON prompting since this vLLM deployment
      has no native tool-parser enabled — model-agnostic ReAct pattern.)
  4. Execute the model's chosen MCP tool call through the gateway.
  5. Feed the observation back; the LLM produces the final answer.

Every hop is real: RHBK OIDC -> Envoy jwt_authn edge -> Kuadrant MCP gateway
-> MemPalace tools ; reasoning by Granite served through MaaS/LiteLLM.
"""
import json, sys, ssl, urllib.request, urllib.parse, re

# ---- endpoints ----
KC   = "https://mcp-keycloak.apps.ocp-gb.ibm.redhataicatalyst.com/realms/mcp"
MCP  = "https://mcp-secure.apps.ocp-gb.ibm.redhataicatalyst.com/mcp"
LLM  = "https://litemaas-litellm-litemaas.apps.ocp-gb.ibm.redhataicatalyst.com/v1/chat/completions"
MODEL = "granite-31-8b-lab-v1"

CLIENT_ID = "mcp-gateway-client"
import os
CLIENT_SECRET = os.environ["MCP_CLIENT_SECRET"]
LLM_KEY = os.environ["LITELLM_KEY"]

CTX = ssl.create_default_context()

def http(url, data=None, headers=None, method=None):
    h = {"Content-Type": "application/json"}
    if headers: h.update(headers)
    body = None
    if data is not None:
        body = data if isinstance(data, bytes) else json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, headers=h, method=method or ("POST" if body else "GET"))
    with urllib.request.urlopen(req, context=CTX, timeout=90) as r:
        return r.status, dict(r.headers), r.read().decode()

def form(url, fields):
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type":"application/x-www-form-urlencoded"}, method="POST")
    with urllib.request.urlopen(req, context=CTX, timeout=60) as r:
        return json.loads(r.read().decode())

def parse_body(text):
    """Handle plain JSON or SSE (data: {...}) responses."""
    t = text.strip()
    if t.startswith("{") or t.startswith("["):
        return json.loads(t)
    for line in t.splitlines():
        line = line.strip()
        if line.startswith("data:"):
            payload = line[5:].strip()
            if payload and payload != "[DONE]":
                try: return json.loads(payload)
                except Exception: pass
    raise ValueError(f"unparseable body: {t[:200]}")

def log(step, msg): print(f"\033[0;36m[{step}]\033[0m {msg}")

# ---- 1. OIDC token ----
def get_token():
    tok = form(f"{KC}/protocol/openid-connect/token",
               {"grant_type":"client_credentials","client_id":CLIENT_ID,"client_secret":CLIENT_SECRET})
    return tok["access_token"]

# ---- MCP plumbing ----
_session = {"id": None}
def mcp(method, params, token, notif=False):
    hdr = {"Authorization": f"Bearer {token}", "Accept":"application/json, text/event-stream"}
    if _session["id"]: hdr["Mcp-Session-Id"] = _session["id"]
    payload = {"jsonrpc":"2.0","method":method,"params":params}
    if not notif: payload["id"] = 1
    status, rh, text = http(MCP, data=payload, headers=hdr)
    sid = rh.get("Mcp-Session-Id") or rh.get("mcp-session-id")
    if sid: _session["id"] = sid
    if notif or not text.strip():
        return None
    d = parse_body(text)
    if "error" in d: raise RuntimeError(f"MCP error on {method}: {d['error']}")
    return d.get("result")

# ---- LLM ----
def llm(messages, max_tokens=500):
    status, _, text = http(LLM, data={"model":MODEL,"messages":messages,"max_tokens":max_tokens,"temperature":0.2},
                           headers={"Authorization":f"Bearer {LLM_KEY}"})
    d = json.loads(text)
    return d["choices"][0]["message"]["content"]

def extract_json(s):
    """Pull the first {...} JSON object out of model output."""
    depth=0; start=-1
    for i,c in enumerate(s):
        if c=="{":
            if depth==0: start=i
            depth+=1
        elif c=="}":
            depth-=1
            if depth==0 and start>=0:
                try: return json.loads(s[start:i+1])
                except Exception: start=-1
    return None

def main():
    task = sys.argv[1] if len(sys.argv)>1 else \
        "Check the status of my memory palace and report how many wings, rooms, and drawers it has."
    print("="*70)
    print("  MaaS LLM  <->  MCP  round-trip  (full OpenShift AI stack)")
    print("="*70)
    log("AUTH", "requesting RHBK OIDC token (client_credentials)…")
    token = get_token()
    log("AUTH", f"got JWT ({len(token)} chars) — will authenticate to the MCP edge")

    log("MCP", "initialize via OIDC-secured edge…")
    init = mcp("initialize", {"protocolVersion":"2025-03-26","capabilities":{},
                              "clientInfo":{"name":"maas-mcp-agent","version":"1.0"}}, token)
    log("MCP", f"gateway: {init.get('serverInfo',{}).get('name')} (session={_session['id']})")
    try: mcp("notifications/initialized", {}, token, notif=True)
    except Exception: pass

    tools = mcp("tools/list", {}, token).get("tools", [])
    log("MCP", f"discovered {len(tools)} federated tools")
    catalog = "\n".join(f'- {t["name"]}: {t.get("description","")}' for t in tools[:40])

    sys_prompt = (
        "You are an assistant with access to MemPalace tools via an MCP gateway.\n"
        "To use a tool, reply with ONLY a JSON object: "
        '{"tool":"<tool_name>","arguments":{...}}\n'
        'When you have enough information, reply with ONLY: {"answer":"<final answer>"}\n'
        "Use exact tool names from this list:\n" + catalog
    )
    messages = [{"role":"system","content":sys_prompt},{"role":"user","content":task}]
    log("TASK", task)

    for step in range(1, 5):
        log("LLM", f"turn {step}: asking MaaS Granite to decide…")
        out = llm(messages)
        decision = extract_json(out)
        if not decision:
            log("LLM", f"non-JSON reply, treating as final: {out[:200]}")
            print("\n\033[0;32mFINAL:\033[0m", out.strip()); return
        if "answer" in decision:
            print("\n\033[0;32m=== FINAL ANSWER (MaaS Granite, informed by MCP tools) ===\033[0m")
            print(decision["answer"]); return
        tool = decision.get("tool"); args = decision.get("arguments",{}) or {}
        log("LLM", f"chose tool: {tool}({json.dumps(args)})")
        log("MCP", f"executing {tool} through the OIDC-secured gateway…")
        try:
            res = mcp("tools/call", {"name":tool,"arguments":args}, token)
            content = res.get("content", res)
            obs = content[0]["text"] if isinstance(content,list) and content and "text" in content[0] else json.dumps(content)
        except Exception as e:
            obs = f"tool error: {e}"
        log("MCP", f"observation: {obs[:200]}")
        messages.append({"role":"assistant","content":json.dumps(decision)})
        messages.append({"role":"user","content":f"Tool result: {obs}\nContinue (JSON only)."})
    print("\n(reached step limit)")

if __name__=="__main__":
    main()
