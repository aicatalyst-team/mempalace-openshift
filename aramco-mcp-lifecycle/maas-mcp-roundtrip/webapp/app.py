#!/usr/bin/env python3
"""
Hosted demo: MaaS LLM <-> MCP round trip, with a web UI that visualizes each hop.
Self-contained (stdlib for HTTP to services + FastAPI for the UI/API).

Env (all have sane defaults for the api.ocp-gb cluster):
  KC_URL, MCP_URL, LLM_URL, MODEL, MCP_CLIENT_ID
  MCP_CLIENT_SECRET  (required)   LITELLM_KEY (required)
"""
import os, json, ssl, urllib.request, urllib.parse
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse

KC   = os.environ.get("KC_URL",  "https://mcp-keycloak.apps.ocp-gb.ibm.redhataicatalyst.com/realms/mcp")
MCP  = os.environ.get("MCP_URL", "https://mcp-secure.apps.ocp-gb.ibm.redhataicatalyst.com/mcp")
LLM  = os.environ.get("LLM_URL", "https://litemaas-litellm-litemaas.apps.ocp-gb.ibm.redhataicatalyst.com/v1/chat/completions")
MODEL = os.environ.get("MODEL", "granite-31-8b-lab-v1")
CLIENT_ID = os.environ.get("MCP_CLIENT_ID", "mcp-gateway-client")
CLIENT_SECRET = os.environ.get("MCP_CLIENT_SECRET", "")
LLM_KEY = os.environ.get("LITELLM_KEY", "")
CTX = ssl.create_default_context()

def _http(url, data=None, headers=None):
    h = {"Content-Type": "application/json"}
    if headers: h.update(headers)
    body = json.dumps(data).encode() if isinstance(data, (dict, list)) else data
    req = urllib.request.Request(url, data=body, headers=h, method="POST" if body else "GET")
    with urllib.request.urlopen(req, context=CTX, timeout=90) as r:
        return r.status, dict(r.headers), r.read().decode()

def _form(url, fields):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(fields).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded"}, method="POST")
    with urllib.request.urlopen(req, context=CTX, timeout=60) as r:
        return json.loads(r.read().decode())

def _parse(text):
    t = text.strip()
    if t[:1] in "{[": return json.loads(t)
    for line in t.splitlines():
        if line.strip().startswith("data:"):
            p = line.strip()[5:].strip()
            if p and p != "[DONE]":
                try: return json.loads(p)
                except Exception: pass
    raise ValueError("unparseable body")

def _extract_json(s):
    depth = 0; start = -1
    for i, c in enumerate(s):
        if c == "{":
            if depth == 0: start = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                try: return json.loads(s[start:i+1])
                except Exception: start = -1
    return None

def run_roundtrip(task):
    steps = []
    def step(layer, detail): steps.append({"layer": layer, "detail": detail})

    tok = _form(f"{KC}/protocol/openid-connect/token",
                {"grant_type": "client_credentials", "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET})["access_token"]
    step("RHBK OIDC", f"issued JWT ({len(tok)} chars) via client_credentials")

    session = {"id": None}
    def mcp(method, params, notif=False):
        hdr = {"Authorization": f"Bearer {tok}", "Accept": "application/json, text/event-stream"}
        if session["id"]: hdr["Mcp-Session-Id"] = session["id"]
        payload = {"jsonrpc": "2.0", "method": method, "params": params}
        if not notif: payload["id"] = 1
        _, rh, text = _http(MCP, data=payload, headers=hdr)
        sid = rh.get("Mcp-Session-Id") or rh.get("mcp-session-id")
        if sid: session["id"] = sid
        if notif or not text.strip(): return None
        d = _parse(text)
        if "error" in d: raise RuntimeError(d["error"])
        return d.get("result")

    init = mcp("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                              "clientInfo": {"name": "maas-mcp-demo", "version": "1.0"}})
    step("Envoy edge", "JWT validated → 200 (401 if missing/invalid)")
    step("MCP Gateway", f"initialized: {init.get('serverInfo', {}).get('name')}")
    try: mcp("notifications/initialized", {}, notif=True)
    except Exception: pass
    tools = mcp("tools/list", {}).get("tools", [])
    step("MCP Gateway", f"discovered {len(tools)} federated tools")
    catalog = "\n".join(f'- {t["name"]}: {t.get("description","")}' for t in tools[:40])

    sys_prompt = ("You are an assistant with access to MemPalace tools via an MCP gateway.\n"
                  'To use a tool, reply ONLY with JSON: {"tool":"<name>","arguments":{...}}\n'
                  'When done, reply ONLY with: {"answer":"<final answer>"}\n'
                  "Use exact tool names from:\n" + catalog)
    messages = [{"role": "system", "content": sys_prompt}, {"role": "user", "content": task}]

    answer = None
    for _ in range(4):
        _, _, text = _http(LLM, data={"model": MODEL, "messages": messages, "max_tokens": 500, "temperature": 0.2},
                           headers={"Authorization": f"Bearer {LLM_KEY}"})
        out = json.loads(text)["choices"][0]["message"]["content"]
        decision = _extract_json(out)
        if not decision:
            answer = out.strip(); break
        if "answer" in decision:
            step("MaaS Granite", "synthesized final answer")
            answer = decision["answer"]; break
        tname = decision.get("tool"); args = decision.get("arguments", {}) or {}
        step("MaaS Granite", f"chose tool: {tname}({json.dumps(args)})")
        try:
            res = mcp("tools/call", {"name": tname, "arguments": args})
            content = res.get("content", res)
            obs = content[0]["text"] if isinstance(content, list) and content and "text" in content[0] else json.dumps(content)
        except Exception as e:
            obs = f"tool error: {e}"
        step("MemPalace", f"{tname} → {obs[:180]}")
        messages.append({"role": "assistant", "content": json.dumps(decision)})
        messages.append({"role": "user", "content": f"Tool result: {obs}\nContinue (JSON only)."})
    return {"steps": steps, "answer": answer or "(no answer)"}

app = FastAPI(title="MaaS ↔ MCP round trip")

@app.get("/healthz")
def healthz(): return {"ok": True}

@app.post("/run")
async def run(req: Request):
    body = await req.json()
    task = (body or {}).get("task") or "Check my memory palace status and summarize."
    try:
        return JSONResponse(run_roundtrip(task))
    except Exception as e:
        return JSONResponse({"error": str(e), "steps": []}, status_code=500)

PAGE = """<!doctype html><html><head><meta charset=utf-8><title>MaaS ↔ MCP — OpenShift AI stack</title>
<meta name=viewport content="width=device-width,initial-scale=1">
<style>
 body{font-family:'Red Hat Text',Arial,sans-serif;margin:0;background:#f4f4f4;color:#151515}
 header{background:#151515;color:#fff;padding:18px 28px}
 header b{color:#ee0000}
 .wrap{max-width:980px;margin:24px auto;padding:0 18px}
 .card{background:#fff;border:1px solid #d2d2d2;border-radius:8px;padding:20px;margin-bottom:18px}
 input{width:100%;padding:12px;font-size:15px;border:1px solid #8a8d90;border-radius:4px;box-sizing:border-box}
 button{margin-top:12px;background:#ee0000;color:#fff;border:0;padding:12px 22px;font-size:15px;border-radius:4px;cursor:pointer}
 button:disabled{background:#b8b8b8}
 .step{display:flex;gap:12px;padding:10px 0;border-bottom:1px solid #eee;align-items:flex-start}
 .layer{flex:0 0 130px;font-weight:700;color:#06c}
 .detail{flex:1;white-space:pre-wrap;font-family:'Red Hat Mono',monospace;font-size:13px;color:#333}
 .answer{background:#e7f1fa;border-left:4px solid #06c;padding:16px;border-radius:4px;white-space:pre-wrap;line-height:1.6}
 .pipe{color:#666;font-size:13px;margin:6px 0 16px}
 .spin{display:none;color:#06c;font-weight:700}
</style></head><body>
<header><h2 style=margin:0>Red Hat OpenShift AI — <b>MaaS LLM ⟷ MCP</b> round trip</h2></header>
<div class=wrap>
 <div class=card>
  <div class=pipe>RHBK OIDC → Envoy jwt_authn edge → Kuadrant MCP Gateway → MaaS Granite → MemPalace (ChromaDB) → grounded answer</div>
  <input id=task placeholder="Ask something that needs the memory palace…"
   value="Search my memory palace for how OIDC authentication is enforced on the MCP gateway, then summarize.">
  <button id=go onclick=runit()>Run round trip</button>
  <span id=spin class=spin>&nbsp;running…</span>
 </div>
 <div class=card id=out style=display:none>
  <h3>Pipeline</h3><div id=steps></div>
  <h3 style=margin-top:20px>Answer (MaaS Granite, grounded in MCP tools)</h3>
  <div class=answer id=answer></div>
 </div>
</div>
<script>
async function runit(){
 const b=document.getElementById('go'),s=document.getElementById('spin');
 b.disabled=true;s.style.display='inline';
 document.getElementById('out').style.display='none';
 try{
  const r=await fetch('/run',{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({task:document.getElementById('task').value})});
  const d=await r.json();
  const sc=document.getElementById('steps');sc.innerHTML='';
  (d.steps||[]).forEach(st=>{const e=document.createElement('div');e.className='step';
    e.innerHTML='<div class=layer>'+st.layer+'</div><div class=detail>'+
      (st.detail||'').replace(/</g,'&lt;')+'</div>';sc.appendChild(e);});
  document.getElementById('answer').textContent=d.answer||d.error||'(no answer)';
  document.getElementById('out').style.display='block';
 }catch(e){alert('error: '+e);}finally{b.disabled=false;s.style.display='none';}
}
</script></body></html>"""

@app.get("/", response_class=HTMLResponse)
def index(): return PAGE
