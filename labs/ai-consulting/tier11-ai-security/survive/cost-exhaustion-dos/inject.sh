#!/usr/bin/env bash
# SURVIVE inject: cost-exhaustion denial of service.
#
# OWASP GenAI: LLM10 Unbounded Consumption. Every /ask call costs money (tokens)
# and compute. With no rate limit and no budget cap, an attacker fires a flood
# of requests - or a few enormous prompts - and runs up your bill or starves
# real users. You must add a rate limit AND a budget cap, then prove they hold.
#
# SELF-CONTAINED. Builds ~/t11-cost-dos with an assistant that meters an
# (estimated) token cost per call but enforces NO limit, plus a flood tool.
# Run as ec2-user on CentOS Stream 9. No paid key needed - cost is simulated.
set -euo pipefail

LAB="${LAB:-$HOME/t11-cost-dos}"
PORT="${PORT:-8000}"

echo "[inject] building a self-contained assistant under $LAB ..."
rm -rf "$LAB"
mkdir -p "$LAB"
cd "$LAB"

cat > llm.py <<'PY'
"""Mock LLM. Returns a canned answer; cost is estimated from input length."""
import os


def complete(system, user, max_tokens=512):
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        return "Answer (mock)."
    import anthropic  # noqa: PLC0415
    client = anthropic.Anthropic(api_key=key)
    r = client.messages.create(model="claude-sonnet-4-6", max_tokens=max_tokens,
                               system=system,
                               messages=[{"role": "user", "content": user}])
    return "".join(b.text for b in r.content if b.type == "text")
PY

cat > app.py <<'PY'
from fastapi import FastAPI
from pydantic import BaseModel
import llm

app = FastAPI()
SYSTEM = "You are an assistant. Be concise."

# Simulated spend meter. Each call adds an estimated cost; there is NO cap and
# NO rate limit, so a flood runs the meter to the moon.
SPEND = {"usd": 0.0}
COST_PER_1K_TOKENS = 0.003  # pretend pricing


def est_cost(text: str) -> float:
    tokens = max(1, len(text) // 4)  # rough: ~4 chars per token
    return (tokens / 1000.0) * COST_PER_1K_TOKENS


class Ask(BaseModel):
    question: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/spend")
def spend():
    return {"usd": round(SPEND["usd"], 4)}


@app.post("/ask")
def ask(body: Ask):
    # VULNERABLE: no rate limit, no budget cap. Every call just spends.
    SPEND["usd"] += est_cost(body.question)
    return {"answer": llm.complete(SYSTEM, body.question),
            "spend_usd": round(SPEND["usd"], 4)}
PY

cat > requirements.txt <<'REQ'
fastapi==0.115.0
uvicorn==0.30.6
pydantic==2.9.2
REQ

# A flood tool: hammer /ask and watch the spend meter climb without limit.
cat > flood.py <<'PY'
import json
import os
import urllib.request

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8000")
N = int(os.environ.get("N", "200"))
big = "please summarize this: " + ("data " * 500)  # a large, costly prompt

ok = 0
blocked = 0
last = {}
for _ in range(N):
    data = json.dumps({"question": big}).encode()
    req = urllib.request.Request(f"{BASE}/ask", data=data,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            last = json.loads(r.read())
            ok += 1
    except urllib.error.HTTPError as e:
        blocked += 1  # 429 rate-limit or 402 budget-cap = the defense working
        continue
print(f"accepted={ok} blocked={blocked}")
try:
    with urllib.request.urlopen(f"{BASE}/spend", timeout=5) as r:
        print("final spend:", json.loads(r.read()))
except Exception as exc:  # noqa: BLE001
    print("spend check failed:", exc)
PY

if [ ! -x .venv/bin/python ]; then
  python3.12 -m venv .venv
  .venv/bin/pip install -q -r requirements.txt
fi

pkill -f "app:app.*$PORT" 2>/dev/null || true
sleep 1
nohup .venv/bin/uvicorn app:app --host 127.0.0.1 --port "$PORT" > server.log 2>&1 &
sleep 4

echo "[inject] DONE. Flood the assistant and watch spend climb with no limit:"
echo "[inject]   cd $LAB && .venv/bin/python flood.py"
echo "[inject] Then follow runbook.md to add a rate limit + budget cap."
