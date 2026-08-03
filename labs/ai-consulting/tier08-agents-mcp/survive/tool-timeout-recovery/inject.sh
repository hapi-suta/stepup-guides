#!/usr/bin/env bash
# SURVIVE inject: a tool TIMES OUT (or errors) mid-plan and the agent must
# recover WITHOUT corrupting its state.
#
# The failure: a tool call to a flaky dependency hangs past its deadline (or
# raises). In the "before" state the harness has no timeout and no error
# handling, so the exception propagates and CRASHES the agent mid-run - leaving
# a half-written report and a corrupt state. The right behavior is to catch the
# failure, turn it into an observation the model can see, and let the agent
# recover with a fallback.
#
# What this does:
#   - Writes a self-contained scenario (scenario.py). config.json controls
#     whether the harness protects tool calls. BEFORE: unprotected -> crash.
#     AFTER: timeout + error-as-observation -> graceful recovery.
#   - Everything runs on a MOCK model - no API key.
#
# Run on the lab server (CentOS Stream 9), as ec2-user, from this directory:
#   bash inject.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "[inject] writing the scenario with UNPROTECTED tool calls (crash state)..."

cat > scenario.py <<'PY'
"""Self-contained tool-timeout scenario. Mock model, stdlib only.

config.json:
  PROTECT_TOOLS - if False, tool calls are unprotected (a timeout/error crashes
                  the run). If True, each tool call has a timeout AND errors are
                  caught and returned to the model as an observation (the fix).

The mock model's plan: call the flaky metrics tool first; if that observation is
an error, fall back to a cached-metrics tool and finish the report. This only
works when the harness turns the failure into an observation instead of crashing.
"""
import json, os, signal, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(HERE, "config.json")
TOOL_TIMEOUT_SECONDS = 2

def load_config():
    with open(CONFIG_FILE) as fh:
        return json.load(fh)

class ToolTimeout(Exception):
    pass

def tool_live_metrics(instance):
    # Simulates a hung dependency: sleeps far past the deadline.
    import time
    time.sleep(30)
    return {"cpu_pct": 50, "instance": instance}

def tool_cached_metrics(instance):
    # A safe fallback that always returns quickly.
    return {"cpu_pct": 47, "instance": instance, "source": "cache"}

TOOLS = {"live_metrics": tool_live_metrics, "cached_metrics": tool_cached_metrics}

def _run_with_timeout(fn, kwargs, seconds):
    """Run fn with a hard timeout using SIGALRM (Unix). Raises ToolTimeout."""
    def _handler(signum, frame):
        raise ToolTimeout(f"tool exceeded {seconds}s deadline")
    old = signal.signal(signal.SIGALRM, _handler)
    signal.alarm(seconds)
    try:
        return fn(**kwargs)
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old)

def mock_model(goal, transcript):
    if not transcript:
        return {"type": "tool_use", "name": "live_metrics", "input": {"instance": "pg-prod-1"}}
    last = transcript[-1]
    # Recovery: if live_metrics failed, fall back to cached_metrics.
    if last["tool"] == "live_metrics" and last.get("is_error"):
        if not any(t["tool"] == "cached_metrics" for t in transcript):
            return {"type": "tool_use", "name": "cached_metrics", "input": {"instance": "pg-prod-1"}}
    return {"type": "final", "text": "report written"}

def run(goal):
    cfg = load_config()
    protect = cfg["PROTECT_TOOLS"]
    transcript = []
    audit = []
    crashed = False
    report_written = False
    for _ in range(10):
        step = mock_model(goal, transcript)
        if step["type"] == "final":
            report_written = True
            audit.append({"event": "final"})
            break
        name = step["name"]
        kwargs = step.get("input", {})
        if protect:
            # FIX: timeout + error-as-observation. One flaky tool never crashes the run.
            try:
                result = _run_with_timeout(TOOLS[name], kwargs, TOOL_TIMEOUT_SECONDS)
                audit.append({"event": "tool_call", "name": name, "ok": True})
                transcript.append({"tool": name, "is_error": False, "result": result})
            except Exception as exc:  # noqa: BLE001
                audit.append({"event": "tool_call", "name": name, "ok": False, "error": str(exc)})
                transcript.append({"tool": name, "is_error": True, "result": f"ERROR: {exc}"})
        else:
            # BEFORE: unprotected. A hang/exception here crashes the whole run.
            # We give the demo its own short alarm ONLY so it does not hang your
            # terminal - but there is NO catch, so it propagates like a real crash.
            def _boom(signum, frame):
                raise ToolTimeout("tool hung and there was no error handling")
            signal.signal(signal.SIGALRM, _boom)
            signal.alarm(TOOL_TIMEOUT_SECONDS)
            result = TOOLS[name](**kwargs)   # <-- crashes here in the before state
            signal.alarm(0)
            audit.append({"event": "tool_call", "name": name, "ok": True})
            transcript.append({"tool": name, "is_error": False, "result": result})
    return {"report_written": report_written, "audit": audit, "crashed": crashed}

if __name__ == "__main__":
    try:
        print(json.dumps(run("Check pg-prod-1 and write a report.")))
    except Exception as exc:  # noqa: BLE001
        # The crash is the symptom in the before state. Record it as JSON so the
        # validator/inject can read a clean result either way.
        print(json.dumps({"report_written": False, "crashed": True, "error": str(exc), "audit": []}))
        sys.exit(0)
PY

# BEFORE state: tool calls unprotected.
cat > config.json <<'JSON'
{"PROTECT_TOOLS": false}
JSON

echo "[inject] running the agent while a tool hangs (UNPROTECTED)..."
python3 scenario.py > last_run.json
echo "[inject] result: $(cat last_run.json)"
echo "[inject] DONE. The hung tool crashed the run mid-plan (no report). Fix the"
echo "[inject]       harness per runbook.md, then run validate.sh."
