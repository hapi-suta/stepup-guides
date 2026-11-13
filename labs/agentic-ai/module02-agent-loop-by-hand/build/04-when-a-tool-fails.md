# Build 04: When a Tool Fails

**Objective:** Make a tool fail on purpose and watch the guardrails work: the program does not crash, the failure is logged with `is_error: true`, and the model reads the error and adjusts.

**Estimated Time:** 15-20 minutes

**Prerequisites:**
- Build 03 of this module finished (`agent.py` runs)

---

## Why this matters

Real tools fail all the time: a path is wrong, a server is down, a permission is missing. A program that crashes on the first tool error is useless as an agent. A program that hides the error is dangerous, because the model then guesses. The right behavior is the one you built in Build 03: catch the error, log it, and tell the model.

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Ask about a directory that does not exist

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python agent.py "How full is the filesystem that holds /data/pgdata?"
```

There is no `/data/pgdata` on your server, so `disk_usage` will raise an `OSError` (file not found).

Expected output (yours will differ):

```text
[turn 1] tool call: disk_usage {"path": "/data/pgdata"}
[turn 2] tool call: disk_usage {"path": "/data"}

The filesystem holding `/data` is 15% used, with 8 GB free of 9 GB.

`/data/pgdata` itself doesn't exist on this host, so I checked `/data` instead. That's the same filesystem only if `/data/pgdata` isn't a separate mount. ...

turns: 3   stop reason: end_turn   cost: $0.000416
```

Turn 1 failed. Your code caught the error and sent it back with `is_error: true`. In turn 2 the model read the error and checked the nearest directory that does exist (yours may pick `/` instead). It also told you plainly what it could not check. The exact recovery differs between runs; the point is that the program kept going and the model knew.

---

## Step 3 - Find the failure in the audit log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
grep '"is_error": true' logs/tool_calls.jsonl
```

`grep` keeps only the lines containing `"is_error": true`: the failed tool calls.

Expected output (yours will differ):

```text
{"turn": 1, "tool": "disk_usage", "input": {"path": "/data/pgdata"}, "is_error": true}
```

This is how you would spot a broken tool in production: count the `is_error` lines per tool, the same way you watch the error rate in `pg_stat_database`.

---

## Step 4 - Count turns per run

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "import json; [print(r['turns'], r['stop_reason'], r['cost_usd']) for r in map(json.loads, open('logs/runs.jsonl'))]"
```

This prints three fields from every run in `logs/runs.jsonl`: turns, stop reason and cost.

Expected output (yours will differ):

```text
2 end_turn 0.0004411
3 end_turn 0.0004163
```

The failed tool cost one extra turn. Each extra turn resends the whole conversation, so errors cost money as well as time. This is why good tool descriptions and clear error messages are a cost control, not just a nicety.
