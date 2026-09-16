#!/usr/bin/env python3
"""
MaaS LLM  <->  MCP round-trip agent (full OpenShift AI stack demo).

Flow:
  1. Authenticate to the OIDC-secured MCP edge (RHBK JWT).
  2. MCP initialize + tools/list  -> discover MemPalace and OpenShift tools via the gateway.
  3. Ask the MaaS-hosted Granite LLM (LiteLLM) to solve a task, offering the tools.
     (Tool use is driven by structured JSON prompting since this vLLM deployment
      has no native tool-parser enabled — model-agnostic ReAct pattern.)
  4. Run read-only grounding probes against both MCP backends through the gateway.
  5. Feed the observations back; Granite produces the final answer and may choose
     additional MCP tools.

Every hop is real: RHBK OIDC -> Envoy jwt_authn edge -> Kuadrant MCP gateway
-> MemPalace + OpenShift MCP tools ; reasoning by Granite served through MaaS/LiteLLM.
"""
import json, sys, ssl, urllib.request, urllib.parse, re, time
from webapp.telemetry import RunTelemetry

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
_active_telemetry = None
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
    global _active_telemetry
    task = sys.argv[1] if len(sys.argv)>1 else \
        "Check the OpenShift AI MCP gateway and my memory palace, then summarize the running MCP services."
    telemetry = RunTelemetry("cli", task)
    telemetry.start()
    _active_telemetry = telemetry
    tool_calls = 0
    def finish_telemetry(success, error=None, metrics=None):
        info = telemetry.finish(success, error, metrics)
        if info.get("url"):
            log("MLFLOW", info["url"])
    print("="*70)
    print("  MaaS LLM  <->  MCP  round-trip  (full OpenShift AI stack)")
    print("="*70)
    log("AUTH", "requesting RHBK OIDC token (client_credentials)…")
    started = time.perf_counter()
    token = get_token()
    telemetry.event("oidc_token", (time.perf_counter() - started) * 1000, "RHBK client_credentials token issued", "RHBK OIDC")
    log("AUTH", f"got JWT ({len(token)} chars) — will authenticate to the MCP edge")

    log("MCP", "initialize via OIDC-secured edge…")
    started = time.perf_counter()
    init = mcp("initialize", {"protocolVersion":"2025-03-26","capabilities":{},
                              "clientInfo":{"name":"maas-mcp-agent","version":"1.0"}}, token)
    telemetry.event("mcp_initialize", (time.perf_counter() - started) * 1000, "MCP session initialized", "MCP Gateway")
    log("MCP", f"gateway: {init.get('serverInfo',{}).get('name')} (session={_session['id']})")
    try: mcp("notifications/initialized", {}, token, notif=True)
    except Exception: pass

    started = time.perf_counter()
    tools = mcp("tools/list", {}, token).get("tools", [])
    telemetry.event("mcp_tools_list", (time.perf_counter() - started) * 1000, f"{len(tools)} federated tools", "MCP Gateway")
    telemetry.metric("tools_discovered", len(tools))
    log("MCP", f"discovered {len(tools)} federated tools")
    catalog = "\n".join(f'- {t["name"]}: {t.get("description","")}' for t in tools[:80])

    # Make the two-server demonstration deterministic while leaving any
    # additional tool selection to Granite. Both probes are read-only.
    used_servers = set()
    grounding = []
    for server, tool, args in [
        ("OpenShift MCP", "resources_get", {"apiVersion": "apps/v1", "kind": "Deployment", "name": "openshift-mcp", "namespace": "openshift-mcp"}),
        ("MemPalace", "mempalace_search", {"query": "OIDC gateway architecture"}),
    ]:
        log("MCP", f"grounding probe: {tool} ({server}) through the OIDC-secured gateway…")
        started = time.perf_counter()
        try:
            res = mcp("tools/call", {"name": tool, "arguments": args}, token)
            content = res.get("content", res)
            obs = content[0]["text"] if isinstance(content, list) and content and "text" in content[0] else json.dumps(content)
            used_servers.add(server)
            tool_calls += 1
        except Exception as exc:
            obs = f"tool error: {exc}"
        telemetry.event("mcp_tool_call", (time.perf_counter() - started) * 1000, f"{server}: {tool} (grounding probe)", server)
        grounding.append(f"{server} {tool} result:\n{obs[:1800]}")
        log("MCP", f"grounding observation: {obs[:200]}")

    sys_prompt = (
        "You are an assistant with access to MemPalace and read-only OpenShift cluster tools via one MCP gateway.\n"
        "This is a two-server observability demo. The host has supplied one live read-only observation from each backend; use them in the answer.\n"
        "To use a tool, reply with ONLY a JSON object: "
        '{"tool":"<tool_name>","arguments":{...}}\n'
        'When you have enough information, reply with ONLY: {"answer":"<final answer>"}\n'
        "Use exact tool names from this list:\n" + catalog
    )
    messages = [{"role":"system","content":sys_prompt},{"role":"user","content":
        task + "\n\nLive grounding observations:\n" + "\n\n".join(grounding)}]
    log("TASK", task)

    for step in range(1, 7):
        log("LLM", f"turn {step}: asking MaaS Granite to decide…")
        started = time.perf_counter()
        out = llm(messages)
        telemetry.event(f"llm_turn_{step}", (time.perf_counter() - started) * 1000, "Granite decision", "MaaS Granite")
        decision = extract_json(out)
        if not decision:
            missing = {"MemPalace", "OpenShift MCP"} - used_servers
            if missing and step < 6:
                messages.append({"role":"assistant","content":out})
                messages.append({"role":"user","content":
                    "Do not answer in prose yet. This demo requires a successful tool call from "
                    + " and ".join(sorted(missing)) + ". Return JSON for the missing backend tool now."})
                continue
            log("LLM", f"non-JSON reply, treating as final: {out[:200]}")
            finish_telemetry(True, metrics={"llm_turns": step, "tool_calls": tool_calls})
            print("\n\033[0;32mFINAL:\033[0m", out.strip()); return
        if "answer" in decision:
            missing = {"MemPalace", "OpenShift MCP"} - used_servers
            if missing and step < 6:
                messages.append({"role":"assistant","content":json.dumps(decision)})
                messages.append({"role":"user","content":
                    "This demo requires both MCP backends in the trace. You still need a successful tool call from "
                    + " and ".join(sorted(missing)) + ". Call that backend now, then provide the final JSON answer."})
                continue
            finish_telemetry(True, metrics={"llm_turns": step, "tool_calls": tool_calls})
            print("\n\033[0;32m=== FINAL ANSWER (MaaS Granite, informed by MCP tools) ===\033[0m")
            print(decision["answer"]); return
        tool = decision.get("tool"); args = decision.get("arguments",{}) or {}
        tool_calls += 1
        log("LLM", f"chose tool: {tool}({json.dumps(args)})")
        server = "MemPalace" if str(tool).startswith("mempalace_") else "OpenShift MCP"
        log("MCP", f"executing {tool} ({server}) through the OIDC-secured gateway…")
        started = time.perf_counter()
        try:
            res = mcp("tools/call", {"name":tool,"arguments":args}, token)
            content = res.get("content", res)
            obs = content[0]["text"] if isinstance(content,list) and content and "text" in content[0] else json.dumps(content)
            used_servers.add(server)
        except Exception as e:
            obs = f"tool error: {e}"
        telemetry.event("mcp_tool_call", (time.perf_counter() - started) * 1000, f"{server}: {tool}", server)
        log("MCP", f"observation: {obs[:200]}")
        messages.append({"role":"assistant","content":json.dumps(decision)})
        messages.append({"role":"user","content":f"Tool result: {obs}\nContinue (JSON only)."})
    finish_telemetry(False, "round-trip step limit reached", {"llm_turns": 6, "tool_calls": tool_calls})
    print("\n(reached step limit)")

if __name__=="__main__":
    try:
        main()
    except Exception as exc:
        if _active_telemetry:
            _active_telemetry.finish(False, str(exc))
        raise
