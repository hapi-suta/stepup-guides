# SURVIVE: Bad deploy - execute the rollback

A deploy just shipped model v2 to production. But v2's artifact is corrupt, so
the serving healthcheck fails - production cannot make predictions. This is the
scenario every production ML system must survive: a bad deploy that has to be
reversed fast and safely.

Your job is to detect the bad deploy, execute the rollback procedure to return
to the known-good model v1, prove production is healthy again, and document the
incident. This is Concepts 10.1 (rollback) in action: because the registry
decouples "which model is production" from the model files, rollback is a
pointer change, not a rebuild.

Before you start, run the injector if you have not already:

```
bash inject.sh
```

That builds `~/survive-bad-deploy`, seeds a registry with a good v1 and a broken
v2, ships v2 to production (the bad deploy), and runs the healthcheck so you can
see production is down.

---

## Layer 1: Detect

On your lab server, as ec2-user, move into the working directory. `cd` changes
your current directory so the commands find the files.

```
cd ~/survive-bad-deploy
```

Activate the virtual environment. `source` loads the venv so `python` uses the
interpreter that already has scikit-learn and joblib installed.

```
source .venv/bin/activate
```

Run the healthcheck. This is what a load balancer or deploy gate calls to decide
whether the deploy is healthy. It loads the production model and tries one
prediction.

```
python healthcheck.py
```

Expected output (yours will differ):

```
HEALTH: FAIL - production model v2 did not load/predict: pop from empty list
```

The healthcheck fails on the production model v2. Production is down. Now find
out what the registry thinks is production.

```
python registry.py current
```

Expected output (yours will differ):

```
production run_id: v2
artifact: models/v2.joblib
```

The registry has v2 in production and it is broken. This is a bad deploy. Do not
try to fix v2 under pressure - the safe move is to roll back to the last
known-good model.

---

## Layer 2: Diagnose

See the full history so you know what to roll back to. `registry.py list` prints
every registered model with its stage.

```
python registry.py list
```

Expected output (yours will differ):

```
v1           archived     models/v1.joblib
v2           production   models/v2.joblib
```

v1 is archived - it was the previous production model, and it is the known-good
one to return to. Confirm v1's artifact is actually loadable before you promote
it, so you do not roll back into a second broken model. `python -c` runs a
one-line program; this one loads v1 and prints OK if it works.

```
python -c "import joblib; b=joblib.load('models/v1.joblib'); print('v1 loads OK:', type(b['model']).__name__)"
```

Expected output (yours will differ):

```
v1 loads OK: RandomForestClassifier
```

v1 is healthy. It is safe to roll back to it.

---

## Layer 3: Correct and validate

Execute the rollback. `registry.py rollback` demotes the current (broken)
production model and promotes the most recently archived model - v1 - back to
production. This is the whole point of the registry: recovery is one command.

```
python registry.py rollback
```

Expected output (yours will differ):

```
rolled back: promoted previous run v1 to production
```

Now prove production is healthy again. Run the same healthcheck that failed
before.

```
python healthcheck.py
```

Expected output (yours will differ):

```
HEALTH: OK - production model v1 loaded and predicted
```

The healthcheck passes. Production is serving again on the known-good model.
Confirm the registry pointer:

```
python registry.py current
```

Expected output (yours will differ):

```
production run_id: v1
artifact: models/v1.joblib
```

Now document the incident. Every rollback is an incident and gets a write-up so
the team learns from it. Open the file with vi.

```
vi rollback_incident.md
```

In vi, press `i` to enter insert mode, type your incident report, then press
`Esc` and type `:wq` and press Enter to save and quit. Make sure you mention the
rollback, name v1 as the known-good model, and describe the bad deploy.
Something like:

```markdown
# Incident: bad deploy of v2

## What happened
A bad deploy promoted model v2 to production. v2's artifact was corrupt so the
healthcheck failed and production could not serve predictions.

## Response
Ran the rollback procedure: python registry.py rollback, which promoted the
previous known-good model v1 back to production. Healthcheck passed again.

## Prevention
Add a post-deploy healthcheck gate so a deploy that fails the healthcheck is
rejected automatically. Add a canary (Concepts 10.4): send v2 a small slice of
traffic first so a broken model never reaches 100% of users.
```

Now validate your work. This runs the checker, which confirms production is v1,
the healthcheck passes, and your incident report covers the right points.

```
bash validate.sh
```

Expected output (yours will differ):

```
=== Validating SURVIVE: bad-deploy-rollback ===
OK:   production is v1 (rolled back to the known-good model)
OK:   healthcheck passes (production serves again)
OK:   rollback_incident.md exists
OK:   incident mentions the rollback
OK:   incident names v1 as the known-good model
OK:   incident describes the bad deploy
RESULT: PASS - bad deploy rolled back, production healthy, incident documented
```

If you see RESULT: PASS you have survived the scenario.

---

## The lesson

The reason you could recover in one command is that the deploy was decoupled
from the model: the registry holds a pointer to "production," and rolling back is
flipping that pointer to the last known-good model. A team that copies model
files directly onto servers cannot do this - they have to rebuild under
pressure. The consulting takeaway: an untested rollback is not a plan. Every
production ML system needs a registry-based rollback that someone has actually
run. You just ran it.

Prof. Happy (SUTA Labs)
