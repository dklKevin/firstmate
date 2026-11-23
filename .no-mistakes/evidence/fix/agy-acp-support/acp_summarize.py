import json,sys
for l in open(sys.argv[1]):
    r=json.loads(l); m=r["msg"]
    if r["dir"]=="out" and m.get("method")=="session/prompt": print(f'[{r["t"]}s] >>> USER PROMPT: {m["params"]["prompt"][0]["text"].strip()[:240]}')
    if m.get("method")=="session/update":
        u=m["params"]["update"]; k=u.get("sessionUpdate")
        if k=="agent_message_chunk": print(f'[{r["t"]}s] AGENT: {u["content"].get("text","").strip()[:400]}')
        elif k=="tool_call": print(f'[{r["t"]}s] TOOL_CALL {u.get("name")}: {json.dumps(u.get("rawInput") or u.get("args"))[:400]}')
        elif k=="tool_call_update" and u.get("status") in ("completed","failed"):
            out=(u.get("rawOutput") or {}).get("output","")
            print(f'[{r["t"]}s] TOOL_RESULT {u.get("name")} status={u.get("status")}:\n    ' + out.replace("\r","").strip().replace("\n","\n    ")[:3500])
    elif r["dir"]=="in" and "result" in m and isinstance(m["result"],dict) and "stopReason" in m["result"]: print(f'[{r["t"]}s] <<< TURN COMPLETE stopReason={m["result"]["stopReason"]}')
