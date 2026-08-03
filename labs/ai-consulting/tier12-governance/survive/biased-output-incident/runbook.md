# SURVIVE: Biased-Output Incident - A Model Update Breaks Fairness

## Scenario

An engineer shipped a "small improvement" to your hiring-screen model over the
weekend. On Monday your fairness monitor alerts: the model is now advancing one group
at far below the four-fifths threshold of the other. Real applicants are being screened
by a biased model in production. This is exactly the kind of harmful-output incident
your governance process exists for.

Your job in this SURVIVE scenario:
1. Detect the biased output via the fairness monitor.
2. Diagnose the root cause (what the "improvement" actually changed).
3. Fix it - and, because this is a governance incident, run the incident-reporting
   process end to end, not just patch the code.

The scenario has already been injected into `~/survive-biased-output`.

This runbook uses the SUTA 3-layer structure:
- Layer 1: Detect
- Layer 2: Diagnose
- Layer 3: Fix and verify (including the incident report)

Governance context: this exercises NIST AI RMF (Measure detects it, Manage responds)
and the incident-reporting policy from Concepts 12.5. The deliverable is both a fixed
model and a completed incident report - governance requires the paper trail, not just
the fix.

---

## Layer 1: Detect (the symptom)

### Step 1.1 - Go to the working directory

On your lab server, as ec2-user:

```
cd ~/survive-biased-output
```

`cd` changes into the folder holding the model, the monitor, and its config.

### Step 1.2 - Activate the Python environment

Still on your lab server, as ec2-user:

```
source venv/bin/activate
```

`source` runs the activation script so `python` uses the project environment with
pandas and scikit-learn installed. Your prompt will start with `(venv)`.

### Step 1.3 - Run the fairness monitor

Still on your lab server, as ec2-user (inside the venv):

```
python fairness_monitor.py
```

`python fairness_monitor.py` trains the currently deployed model, computes the
selection rate per group, and reports the disparate-impact ratio.

Expected output (yours will differ):

```
=== FAIRNESS MONITOR (deployed model: v2) ===
  Group A: selection rate = 0.462
  Group B: selection rate = 0.239

Disparate-impact ratio: 0.517
ALERT: below 0.80 four-fifths threshold. BIASED OUTPUT INCIDENT.
```

Symptom confirmed: the deployed model is `v2`, and its ratio (~0.52) is well below
0.80. The monitor exited non-zero - a failing check. This is your incident.

---

## Layer 2: Diagnose (the root cause)

### Step 2.1 - See which model is deployed

Still on your lab server, as ec2-user:

```
cat model_config.txt
```

`cat` prints the config. It selects which model version is live.

Expected output:

```
v2
```

### Step 2.2 - Read the model to see what v2 changed

Still on your lab server, as ec2-user:

```
vi fairness_monitor.py
```

`vi` opens the file. Find the section that chooses `features` based on the version.
You will see:
- `v1` uses `["experience", "skills_score"]` - a balanced feature set.
- `v2` uses `["experience"]` only.

The "improvement" dropped the fair, group-independent `skills_score` feature and left
the model leaning entirely on `experience` - which is correlated with group in this
data. Experience became a **proxy variable** for group, so the model reproduces the
group gap. To quit vi without changing anything, type `:q!` and press Enter.

Root cause: the model update removed a balancing feature, leaving a proxy variable to
drive selection. This is the classic fairness regression from Concepts 12.1 and 12.4 -
dropping the protected attribute (or here, dropping the balancing signal) does not make
a model fair when a proxy remains.

---

## Layer 3: Fix and verify

Governance incidents have two deliverables: fix the harm, and document the incident.
Do both.

### Step 3.1 - Remediate the model (roll back the bad change)

The fastest safe fix is to revert to the balanced version. Still on your lab server,
as ec2-user:

```
vi model_config.txt
```

Press `i`, delete `v2`, type `v1`, then press `Esc`, type `:wq` and press Enter. This
puts the balanced model (experience + skills_score) back into production.

(A more permanent fix would edit `fairness_monitor.py` so even `v2` uses the balanced
feature set. Reverting the config is the correct immediate containment step.)

### Step 3.2 - Confirm the model is fair again

Still on your lab server, as ec2-user (inside the venv):

```
python fairness_monitor.py
```

Expected output (yours will differ):

```
=== FAIRNESS MONITOR (deployed model: v1) ===
  Group A: selection rate = 0.488
  Group B: selection rate = 0.408

Disparate-impact ratio: 0.836
OK: at or above 0.80.
```

The ratio recovered above 0.80 and the monitor now passes. The harm is contained.

### Step 3.3 - File the incident report

The fix is not the end. Governance requires you to record what happened. Copy your
incident template. Still on your lab server, as ec2-user:

```
cp ~/governance-toolkit/09-incident-report-template.md ./biased-output-incident-report.md
```

`cp` copies the template to a real incident file. (If the toolkit is not on this box,
create it with `vi biased-output-incident-report.md` and write the sections from
memory: what happened, when, who was affected, severity, immediate action, root cause,
remediation, notifications, lessons learned.)

Open it:

```
vi biased-output-incident-report.md
```

Press `i` and complete every section for this incident. It MUST mention the **bias**
and the **root cause**. A worked summary you can adapt:
- What happened: a model update advanced group A far more than group B; disparate-impact
  ratio fell to ~0.52, below the 0.80 four-fifths threshold.
- When / detected: shipped over the weekend; detected Monday by the fairness monitor.
- Affected: applicants screened while v2 was live.
- Severity: high (biased decisions about people in production).
- Immediate action: reverted model_config from v2 to v1 (balanced feature set).
- Root cause: v2 dropped the balancing skills_score feature, leaving experience as a
  proxy variable for group.
- Remediation + retest: monitor now reports ratio ~0.84, passing.
- Lessons learned: add the fairness monitor as a blocking check in CI so a model change
  cannot ship if the ratio drops below 0.80; require a fairness review for feature
  changes.

Press `Esc`, type `:wq` and press Enter to save and quit.

### Step 3.4 - Verify with the validator

Still on your lab server, as ec2-user, run the scenario validator (path depends on
where the scenario was placed), for example:

```
bash ~/survive-biased-output/validate.sh
```

It checks that the incident report exists and covers bias + root cause, and that the
fairness monitor now passes.

Expected output (yours will differ):

```
PASS: incident report exists and covers bias + root cause (biased-output-incident-report.md)
PASS: fairness monitor now reports a fair model (ratio >= 0.80)
ALL CHECKS PASSED
```

### Step 3.5 - Leave the environment

Still on your lab server, as ec2-user:

```
deactivate
```

`deactivate` exits the virtual environment; the `(venv)` prefix disappears.

---

## Key takeaways

- Fairness is a monitored metric, not a one-time claim. A model update can break it
  silently - which is why the disparate-impact monitor belongs in your pipeline, ideally
  as a blocking CI check.
- The usual root cause of a fairness regression is a proxy variable. Removing an
  attribute (or a balancing feature) does not make a model fair; a correlated proxy
  carries the bias back in.
- A biased output is a governance incident. The response is contain the harm (roll
  back), find the root cause, remediate, AND file the incident report with lessons
  learned. The paper trail is part of the fix.
- The durable lesson-learned here is prevention: gate model changes on the fairness
  metric so this cannot ship again.

Prof. Happy (SUTA Labs)
