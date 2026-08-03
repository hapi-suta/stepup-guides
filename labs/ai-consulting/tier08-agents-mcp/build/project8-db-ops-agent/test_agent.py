"""Tests for the db-ops agent - all on the MOCK, no API key needed.

Run:  python3 -m pytest test_agent.py -q      (if pytest is installed)
  or: python3 test_agent.py                    (plain runner, no pytest)

These tests are the proof-of-competence checks: the agent never runs a
destructive command, logs every tool call, enforces the approval gate, honors
its limits, and recovers from a tool error.
"""

from __future__ import annotations

import json
import os

import agent

AUDIT = agent.AUDIT_PATH


def _approve_all(name, tool_input):
    return True


def _deny_all(name, tool_input):
    return False


def _read_audit():
    with open(AUDIT, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def test_no_destructive_tool_exists():
    # Least privilege: there is no run_sql / execute / delete tool at all.
    for forbidden in ("run_sql", "execute", "delete", "drop", "shell"):
        assert forbidden not in agent.TOOLS


def test_happy_path_writes_report_and_stops():
    agent.reset_audit()
    res = agent.run("Check pg-prod-1 and write a report.", approver=_approve_all)
    assert res["stopped"] == "model_done"
    assert "INCIDENT REPORT" in res["answer"]
    assert "No destructive command was executed" in res["answer"]


def test_every_tool_call_is_audited():
    agent.reset_audit()
    agent.run("Check pg-prod-1 and write a report.", approver=_approve_all)
    records = _read_audit()
    tool_calls = [r for r in records if r["event"] == "tool_call"]
    # get_db_health, search_runbooks, recommend_action = 3 successful tool calls
    assert len(tool_calls) >= 3
    assert any(r["name"] == "get_db_health" for r in tool_calls)
    assert any(r["event"] == "run_start" for r in records)


def test_action_requires_approval_and_denial_blocks_it():
    agent.reset_audit()
    res = agent.run("Check pg-prod-1 and write a report.", approver=_deny_all)
    records = _read_audit()
    # The action was proposed but DENIED - it must never have executed.
    assert any(r["event"] == "action_denied" for r in records)
    assert not any(r.get("event") == "action_approved" for r in records)
    # The recommend_action tool was never actually run.
    assert not any(r["event"] == "tool_call" and r["name"] == "recommend_action" for r in records)
    # It still finishes and writes a report (no action recommended).
    assert "INCIDENT REPORT" in res["answer"]


def test_tool_call_limit_stops_the_loop():
    agent.reset_audit()
    # A model that loops forever asking for the same read-only tool.
    def looping_model(goal, transcript):
        return {"type": "tool_use", "name": "get_db_health", "input": {"instance": "pg-prod-1"}}

    res = agent.run("loop", model=looping_model, approver=_approve_all, max_tool_calls=5)
    assert res["stopped"] == "max_tool_calls"
    assert res["tool_calls"] == 5


def test_budget_stops_the_loop():
    agent.reset_audit()
    def looping_model(goal, transcript):
        return {"type": "tool_use", "name": "get_db_health", "input": {"instance": "pg-prod-1"}}

    res = agent.run("loop", model=looping_model, approver=_approve_all,
                    max_tool_calls=1000, max_tokens=50)
    assert res["stopped"] == "budget_exhausted"


def test_unknown_tool_is_refused_not_run():
    agent.reset_audit()
    # A model (e.g. hijacked by injection) that asks for a tool that does not exist.
    calls = {"n": 0}
    def rogue_model(goal, transcript):
        calls["n"] += 1
        if calls["n"] == 1:
            return {"type": "tool_use", "name": "run_sql", "input": {"sql": "DROP TABLE users"}}
        return {"type": "final", "text": "done"}

    res = agent.run("rogue", model=rogue_model, approver=_approve_all)
    records = _read_audit()
    assert any(r["event"] == "tool_refused_unknown" and r["name"] == "run_sql" for r in records)
    # It never became a real tool_call.
    assert not any(r["event"] == "tool_call" and r.get("name") == "run_sql" for r in records)
    assert res["stopped"] == "model_done"


def test_tool_error_becomes_observation_not_crash():
    agent.reset_audit()
    # Asking for an unknown instance raises inside the tool; the agent must
    # recover (turn it into an observation) and still finish.
    calls = {"n": 0}
    def erroring_model(goal, transcript):
        calls["n"] += 1
        if calls["n"] == 1:
            return {"type": "tool_use", "name": "get_db_health", "input": {"instance": "does-not-exist"}}
        return {"type": "final", "text": "handled the error"}

    res = agent.run("err", model=erroring_model, approver=_approve_all)
    records = _read_audit()
    assert any(r["event"] == "tool_call" and r["ok"] is False for r in records)
    assert res["stopped"] == "model_done"


if __name__ == "__main__":
    # Plain runner so the box does not need pytest installed.
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for t in tests:
        try:
            t()
            print(f"PASS  {t.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"FAIL  {t.__name__}: {e}")
        except Exception as e:  # noqa: BLE001
            print(f"ERROR {t.__name__}: {e}")
    print(f"\n{passed}/{len(tests)} tests passed")
    raise SystemExit(0 if passed == len(tests) else 1)
