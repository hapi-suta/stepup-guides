# SURVIVE: Provider Outage

Your LLM feature calls one provider. That provider is down. Because there is no
fallback, every request fails and the feature is completely unavailable - a
single point of failure took the whole thing offline.

In this runbook you will detect the outage, diagnose the real cause (no graceful
degradation), and fix it by adding a fallback to a second provider so the feature
survives.

**No real API and no API key are involved.** Both the primary and the backup are
LOCAL mock LLM servers, so you test the resilience LOGIC (fallback / graceful
degradation) for free. In a real system the "backup" would be a second provider
(a different vendor, a different tier, or a self-hosted model) reached through
your provider abstraction (Concepts 6.3/6.4).

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - find the real cause.
3. Fix and verify - repair it and prove the repair.

---

## Layer 1: Detect

First run the injector so you can see the failure.

On your lab server, as ec2-user:

```
bash inject.sh
```

`bash` runs the script. It builds the working directory, starts ONLY the backup
mock server (the primary is deliberately left down), and runs the broken client.

Expected output (yours will differ):

```
==> Creating working directory: /home/ec2-user/survive-provider-outage
...
==> Running the broken client.py so you can see the failure:
-------------------------------------------------------------
Traceback (most recent call last):
  ...
urllib.error.URLError: <urlopen error [Errno 111] Connection refused>
-------------------------------------------------------------

The client tried the PRIMARY provider (8971), which is down, and gave up -
it never tried the healthy backup on 8972. That single point of failure is
the outage. Open runbook.md and add graceful fallback.
```

`Connection refused` on the primary port is the outage. The feature is dead.

---

## Layer 2: Diagnose

Move into the working directory.

On your lab server, as ec2-user:

```
cd ~/survive-provider-outage
```

Look at the client to see the flaw.

Still on your lab server, as ec2-user:

```
grep -n "def triage" client.py
```

`grep -n` prints matching lines with line numbers.

Expected output (yours will differ):

```
28:def triage(prompt: str) -> dict:
```

Open the file and read the `triage` function.

Still on your lab server, as ec2-user:

```
vi client.py
```

You will see that `triage` calls only the primary provider, with no error
handling and no fallback:

```python
def triage(prompt: str) -> dict:
    # BUG: only ever calls the primary. No try/except, no fallback.
    return call_provider(PRIMARY_PORT, prompt)
```

The real cause is not that the primary is down - providers go down, that is
normal. The real cause is that the code has **no graceful degradation**. A
resilient feature tries a backup when the primary fails (Concepts 6.4, model
fallback). Confirm the backup is actually healthy so you know fallback will work:

Still on your lab server, as ec2-user:

```
curl -s -X POST http://127.0.0.1:8972/ -d '{}'
```

`curl -s` makes a quiet HTTP request; `-X POST` sends a POST; `-d` supplies a body.

Expected output (yours will differ):

```
{"provider": "secondary", "text": "ok from secondary"}
```

The backup responds fine. All we need is for the client to use it when the
primary fails.

---

## Layer 3: Fix and verify

Fix `triage` to fall back to the secondary provider when the primary fails.

Still in vi editing `client.py`, replace the broken `triage` function with a
version that tries the primary, and on ANY failure degrades to the secondary.
Press `i` to enter insert mode and change the function to:

```python
def triage(prompt: str) -> dict:
    # Try the primary provider first. On ANY failure (down, timeout, error),
    # degrade gracefully to the secondary provider instead of failing the
    # whole feature. Never swallow the error silently - log why we fell back.
    try:
        return call_provider(PRIMARY_PORT, prompt)
    except Exception as exc:
        print(f"[warn] primary provider failed ({exc}); falling back to secondary")
        return call_provider(SECONDARY_PORT, prompt)
```

Press `Esc` to leave insert mode, then type `:wq` and press Enter to save and quit.

Now run the client again.

Still on your lab server, as ec2-user:

```
python client.py
```

Expected output (yours will differ):

```
[warn] primary provider failed (<urlopen error [Errno 111] Connection refused>); falling back to secondary
RESULT {"provider": "secondary", "text": "ok from secondary"}
```

Signs of a healthy, resilient feature:

- The client detected the primary outage instead of crashing.
- It logged WHY it fell back (never a silent failure - Concepts 6.4).
- It served a real result from the SECONDARY provider - the feature stayed up.

You have turned a single point of failure into graceful degradation. That is the
survive.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validator. It makes sure the primary is down and the backup is
up, reruns your `client.py`, and checks that it exits cleanly AND that the RESULT
was served by the secondary provider (proving fallback actually happened).

Expected output (yours will differ):

```
Ensuring PRIMARY (8971) is down and SECONDARY (8972) is up ...
Running your client.py with the primary provider down ...
RESULT line: RESULT {"provider": "secondary", "text": "ok from secondary"}
PASS: primary was down, and the client degraded gracefully to the secondary provider.
```

If you see `PASS`, you are done.

---

## Takeaways

- One provider is a single point of failure. Providers WILL have outages - design
  for it, do not hope against it.
- Graceful degradation means: try the primary, and on any failure fall back to a
  backup, so the feature stays available.
- Fallback is cheap once you have a provider abstraction (Concepts 6.3) - the
  backup is just another provider behind the same interface.
- Never swallow the error - log why you fell back, so you can see and fix the
  underlying outage.
- You proved all of this against LOCAL mock servers, with no real API and no key -
  the resilience logic is what matters, and it is fully testable for free.

Prof. Happy (SUTA Labs)
