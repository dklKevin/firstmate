#!/usr/bin/env python3
"""Minimal ACP stdio client that drives a real `antigravity acp` server.

usage: acp_drive.py <transcript.jsonl> <cwd> <prompt-file>...
Each prompt file is sent as one session/prompt turn; timings and stop reasons
are printed. Optional env ACP_BG_PROMPT_AFTER=<sec>: send the next prompt while
the previous one is still running after that many seconds (concurrency probe).
"""
import json, os, subprocess, sys, threading, time, queue

ANTI = os.environ["ANTIGRAVITY_BIN"]
GEMINI_DIR = os.environ["ANTIGRAVITY_GEMINI_DIR"]
transcript_path, cwd, *prompt_files = sys.argv[1:]
log = open(transcript_path, "a")
t0 = time.time()

def stamp(): return round(time.time() - t0, 2)
def rec(direction, obj):
    log.write(json.dumps({"t": stamp(), "dir": direction, "msg": obj}) + "\n"); log.flush()

proc = subprocess.Popen(
    [ANTI, "acp", "--gemini-dir", GEMINI_DIR, "--app-data-dir", "antigravity-acp",
     "--dangerously-skip-permissions"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=open(transcript_path + ".stderr", "w"),
    cwd=cwd, text=True, bufsize=1)
print(f"ACP_SERVER_PID={proc.pid}", flush=True)
open(os.path.join(os.path.dirname(transcript_path), os.path.basename(transcript_path) + ".pid"), "w").write(str(proc.pid))

pending = {}
lock = threading.Lock()
next_id = [0]
updates = queue.Queue()

def send(obj):
    rec("out", obj)
    proc.stdin.write(json.dumps(obj) + "\n"); proc.stdin.flush()

def request(method, params):
    with lock:
        next_id[0] += 1; rid = next_id[0]
        ev = threading.Event(); pending[rid] = [ev, None]
    send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
    return rid, ev

def reader():
    for line in proc.stdout:
        line = line.strip()
        if not line: continue
        try: msg = json.loads(line)
        except Exception:
            rec("in-raw", line); continue
        rec("in", msg)
        if "method" in msg and "id" in msg:
            # server -> client request
            m = msg["method"]
            if m == "session/request_permission":
                opts = msg["params"].get("options", [])
                pick = next((o for o in opts if o.get("kind", "").startswith("allow")), opts[0] if opts else None)
                res = {"outcome": {"outcome": "selected", "optionId": pick["optionId"]}} if pick else {"outcome": {"outcome": "cancelled"}}
                send({"jsonrpc": "2.0", "id": msg["id"], "result": res})
            else:
                send({"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": "not supported"}})
        elif "id" in msg:
            with lock:
                slot = pending.get(msg["id"])
            if slot:
                slot[1] = msg; slot[0].set()
        else:
            updates.put(msg)
threading.Thread(target=reader, daemon=True).start()

def wait(rid, ev, timeout):
    ok = ev.wait(timeout)
    return pending[rid][1] if ok else None

rid, ev = request("initialize", {"protocolVersion": 1, "clientCapabilities": {"fs": {"readTextFile": False, "writeTextFile": False}, "terminal": False}})
r = wait(rid, ev, 60); print("initialize:", "ok" if r and "result" in r else r, flush=True)
rid, ev = request("session/new", {"cwd": cwd, "mcpServers": []})
r = wait(rid, ev, 120)
if not r or "result" not in r:
    print("session/new failed:", r, flush=True); proc.kill(); sys.exit(1)
sid = r["result"]["sessionId"]; print(f"session/new: ok sessionId={sid} at t={stamp()}s", flush=True)

overlap = float(os.environ.get("ACP_BG_PROMPT_AFTER", "0"))
per_turn_timeout = float(os.environ.get("ACP_TURN_TIMEOUT", "300"))
inflight = []
for i, pf in enumerate(prompt_files, 1):
    text = open(pf).read()
    if pf.endswith(".hook"):  # shell hook run by the client between turns
        print(f"[client] running between-turn hook {pf}", flush=True)
        subprocess.run(["bash", pf], check=False); continue
    start = stamp()
    rid, ev = request("session/prompt", {"sessionId": sid, "prompt": [{"type": "text", "text": text}]})
    inflight.append((i, pf, rid, ev, start))
    if overlap and i < len(prompt_files):
        time.sleep(overlap); continue
    for (j, pfj, ridj, evj, startj) in inflight:
        r = wait(ridj, evj, per_turn_timeout)
        end = stamp()
        if r is None:
            print(f"turn {j} ({os.path.basename(pfj)}): NO RESPONSE after {per_turn_timeout}s (sent t={startj}s)", flush=True)
        else:
            sr = r.get("result", {}).get("stopReason") if "result" in r else r.get("error")
            print(f"turn {j} ({os.path.basename(pfj)}): sent t={startj}s completed t={end}s elapsed={round(end-startj,2)}s stopReason={sr}", flush=True)
    inflight = []

grace = float(os.environ.get("ACP_TAIL_SECONDS", "0"))
if grace:
    print(f"[client] tailing updates for {grace}s", flush=True); time.sleep(grace)
proc.terminate()
try: proc.wait(10)
except Exception: proc.kill()
print("server exited", proc.returncode, flush=True)
