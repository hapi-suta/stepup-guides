# SURVIVE: Cloud Region Outage - Fail Over to the Second Cloud

Your AI feature calls one cloud region (the primary, a mock AWS us-east-1). That
region is having an outage. Because the app has no failover, every request fails
and the feature is completely offline - a single region became a single point of
failure. A healthy region on a SECOND cloud (a mock GCP europe-west1) is sitting
right there, unused.

This is the payoff of the multi-cloud portability you built in BUILD Project 13:
because every model call goes through one abstraction, adding failover to the
second cloud is cheap. In this runbook you will detect the outage, diagnose the
real cause (no failover), and fix it so a regional outage becomes a brief
degradation instead of a full stop.

**No real cloud and no credentials are involved.** Both "regions" are LOCAL mock
servers, so you test the failover LOGIC for free. In a real system the secondary
would be a second region or a second cloud reached through your provider
abstraction (Concepts 13.1-13.3).

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - find the real cause.
3. Fix and verify - repair it and prove the repair.

---

## Layer 1: Detect

First run the injector so you can see the outage.

On your lab server, as ec2-user:

```
bash inject.sh
```

`bash` runs the script. It writes a mock region server and a client with no
failover, starts ONLY the secondary region (the primary is left down), and runs
the client.

Expected output (yours will differ):

```
==> Running the broken client.py so you can see the outage failure:
-------------------------------------------------------------
Traceback (most recent call last):
  ...
urllib.error.URLError: <urlopen error [Errno 111] Connection refused>
-------------------------------------------------------------

The primary region (8991) is down and the client has no failover, so the
feature is offline. Open runbook.md and add failover to the second cloud.
```

`Connection refused` on the primary region is the outage. The feature is dead.

---

## Layer 2: Diagnose

Move into the working directory.

On your lab server, as ec2-user:

```
cd ~/survive-region-outage
```

Look at how the client routes requests.

Still on your lab server, as ec2-user:

```
grep -n "def serve" client.py
```

`grep -n` prints matching lines with line numbers.

Expected output (yours will differ):

```
28:def serve(prompt):
```

Open the client and read `serve`.

Still on your lab server, as ec2-user:

```
vi client.py
```

You will see `serve` calls only the primary region, with no error handling and no
failover:

```python
def serve(prompt):
    # BUG: only ever calls the primary region. No failover.
    return call_region(PRIMARY_PORT, prompt)
```

The real cause is not the outage - cloud regions do have outages, that is normal
and expected. The cause is that the app has no failover to a second region or
cloud. Confirm the secondary region is actually healthy so failover will work.

Press `Esc`, type `:q!`, press Enter to leave vi without changing anything yet.
Then, still on your lab server, as ec2-user:

```
curl -s -X POST http://127.0.0.1:8992/ -d '{}'
```

`curl -s` makes a quiet request; `-X POST` sends a POST; `-d` supplies a body.

Expected output (yours will differ):

```
{"region": "gcp-europe-west1", "text": "ok from gcp-europe-west1"}
```

The secondary region responds fine. All the app needs is to use it when the
primary fails.

---

## Layer 3: Fix and verify

Fix `serve` to fail over to the secondary region on any primary failure.

Still on your lab server, as ec2-user:

```
vi client.py
```

Press `i` to enter insert mode. Replace the `serve` function with a version that
tries the primary and, on ANY failure, fails over to the secondary cloud region:

```python
def serve(prompt):
    # FIX: try the primary region; on ANY failure fail over to the second cloud
    # region. Log why, never fail silently.
    try:
        return call_region(PRIMARY_PORT, prompt)
    except Exception as exc:
        print(f"[warn] primary region outage ({exc}); failing over to secondary cloud")
        return call_region(SECONDARY_PORT, prompt)
```

Press `Esc`, type `:wq`, press Enter. Run the client again.

Still on your lab server, as ec2-user:

```
python3 client.py
```

Expected output (yours will differ):

```
[warn] primary region outage (<urlopen error [Errno 111] Connection refused>); failing over to secondary cloud
RESULT {"region": "gcp-europe-west1", "text": "ok from gcp-europe-west1"}
```

Signs of a resilient, multi-cloud feature:

- It detected the primary region outage instead of crashing.
- It logged WHY it failed over (never silent - Concepts 13.1).
- It served a real result from the SECONDARY cloud region - the feature stayed up.

You turned a regional single point of failure into cross-cloud failover. In a
real deployment the same pattern applies at the region level (a second AWS region)
or the cloud level (AWS primary, GCP or Azure secondary) - and it is cheap
precisely because your model calls already go through one abstraction. Always log
the failover so an ongoing outage is visible and not hidden.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validator. It ensures the primary is down and the secondary is
up, reruns your client, and checks that the RESULT was served by the secondary
region (proving failover happened).

Expected output (yours will differ):

```
Ensuring PRIMARY (8991) is down and SECONDARY (8992) is up ...
Running your client.py with the primary region down ...
RESULT line: RESULT {"region": "gcp-europe-west1", "text": "ok from gcp-europe-west1"}
PASS: primary region was down and the client failed over to the secondary cloud region.
```

If you see `PASS`, you are done.

---

Prof. Happy (SUTA Labs)
