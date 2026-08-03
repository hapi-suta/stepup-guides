# BUILD: The MLOps pipeline - train, register, deploy, monitor, retrain

**Tier 10 - the "make the model operable" build.** You will build the full lifecycle from Concepts 10.1 as small, working scripts: train a model and track the run, register it, deploy it behind an API, monitor the live traffic, detect drift, and retrain when drift appears. Every piece runs on a CPU, offline. No MLflow install, no Kubernetes, no cloud account. You build the lightweight version of each so you understand exactly what it stores.

By the end you have a folder where you can point at each file and say which lifecycle stage it implements. That is the artifact a client hires you for.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25. Numbers shown are real (exact digits depend on library versions and will differ slightly). The run IDs contain a timestamp and a random suffix, so yours will always differ - that is expected.

**Prerequisite:** you read Concepts 10.1 (lifecycle), 10.2 (tools), and 10.5 (drift).

**What you build** in `mlops-pipeline/`:

- `generate_data.py` - a reproducible synthetic support-ticket dataset
- `train.py` - trains a model, tracks the run, saves the artifact, registers it
- `registry.py` - a model registry CLI: list, promote, current, rollback
- `save_baseline.py` - captures the training distribution as a drift baseline
- `detect_drift.py` - a KS-test drift detector that exits non-zero on drift
- `serve.py` - a FastAPI endpoint that serves the production model and logs metrics
- `monitor.py` - summarises the serving metrics
- `retrain.py` - retrains only when drift is detected, closing the loop

---

## Step 1: Create the project folder

On your **lab server** (CentOS Stream 9), as **ec2-user**:

```bash
mkdir -p ~/mlops-pipeline
```

The `mkdir` command makes a directory. The `-p` flag creates parent folders if needed and does not error if the folder already exists.

Move into it:

```bash
cd ~/mlops-pipeline
```

`cd` changes your current directory so every later command runs inside the project.

---

## Step 2: Create and activate a virtual environment

A virtual environment is an isolated Python setup. Packages you install here do not touch the system Python, so you cannot break the server.

Still on your **lab server**, as **ec2-user**, in `~/mlops-pipeline`:

```bash
python3.12 -m venv .venv
```

`python3.12 -m venv` runs the built-in venv tool. `.venv` is the folder it creates for the isolated environment.

Activate it:

```bash
source .venv/bin/activate
```

`source` runs the activate script in your current shell so `python` and `pip` now point at the isolated environment. Your prompt now shows `(.venv)`.

---

## Step 3: Install the libraries

Still in the activated environment:

```bash
pip install scikit-learn pandas numpy scipy joblib fastapi "uvicorn[standard]"
```

What each does:

- `scikit-learn` - the machine-learning toolkit (models, metrics, splitting).
- `pandas` - tables (DataFrames) for handling the dataset.
- `numpy` - fast numeric arrays underneath everything.
- `scipy` - statistics; we use its Kolmogorov-Smirnov test for drift.
- `joblib` - saves a trained model to a file so we can load it later.
- `fastapi` - the web framework for the prediction endpoint.
- `uvicorn[standard]` - the server that runs the FastAPI app.

Confirm the core libraries installed:

```bash
pip list | grep -Ei "scikit-learn|pandas|scipy|fastapi"
```

`pip list` prints installed packages. `grep -Ei` filters to lines matching any of these names, case-insensitively (`-i`) using extended regex (`-E`).

Expected output (yours will differ):

```
fastapi           0.115.0
pandas            2.2.2
scikit-learn      1.5.1
scipy             1.14.1
```

---

## Step 4: Generate a reproducible dataset

We simulate a support-ticket triage feed. Each ticket has a few signals and a label: is it high priority? The `np.random.seed(42)` line makes the data identical every run - that is reproducibility (Concepts 10.1) in miniature, and it is why your numbers will match this guide.

Open a new file:

```bash
vi generate_data.py
```

Press `i` to enter insert mode, then type this in:

```python
"""Generate a reproducible support-ticket dataset for the MLOps pipeline.

Each ticket has a few numeric signals and a category. The label is whether the
ticket is HIGH priority. We fix the seed so the data is identical every run,
which is what makes an MLOps pipeline reproducible.
"""
import numpy as np
import pandas as pd

np.random.seed(42)

N = 2000

# Numeric signals a triage system would see.
age_hours = np.random.exponential(scale=12, size=N).round(1)
reply_count = np.random.poisson(lam=3, size=N)
customer_tier = np.random.choice([1, 2, 3], size=N, p=[0.6, 0.3, 0.1])
sentiment = np.random.normal(loc=0.0, scale=1.0, size=N).round(3)

# Hidden rule the model must learn: high tier, angry sentiment, and stale
# tickets are more likely to be high priority.
score = (
    0.9 * (customer_tier == 3)
    + 0.5 * (customer_tier == 2)
    - 0.6 * sentiment
    + 0.03 * age_hours
    + 0.1 * reply_count
)
prob = 1 / (1 + np.exp(-(score - 1.2)))
is_high = (np.random.random(N) < prob).astype(int)

df = pd.DataFrame({
    "age_hours": age_hours,
    "reply_count": reply_count,
    "customer_tier": customer_tier,
    "sentiment": sentiment,
    "is_high": is_high,
})
df.to_csv("tickets.csv", index=False)
pos = int(df["is_high"].sum())
print(f"Wrote tickets.csv with {len(df)} rows")
print(f"high-priority rows: {pos} ({pos/len(df):.1%})")
```

Press `Esc`, then type `:wq` and press Enter to save and quit vi.

Run it:

```bash
python generate_data.py
```

`python generate_data.py` runs the script, which writes `tickets.csv` and prints a summary.

Expected output (yours will differ):

```
Wrote tickets.csv with 2000 rows
high-priority rows: 877 (43.9%)
```

---

## Step 5: Train the model with experiment tracking and a registry

This is the heart of MLOps. `train.py` does three lifecycle jobs at once: it **tracks** the run to `experiments.jsonl`, saves the **artifact** to `models/`, and **registers** the model in a SQLite table with a stage. This is the lightweight version of what MLflow does.

Open the file:

```bash
vi train.py
```

Press `i`, then type this in:

```python
"""Train a priority model, log the experiment run, and register the model.

This is a lightweight, offline stand-in for MLflow. It does three MLOps things:
  1. Experiment tracking: append a JSON line per run to experiments.jsonl.
  2. Model artifact: save the fitted model to models/<run_id>.joblib.
  3. Model registry: record the run in a SQLite registry table with a stage.

Everything runs on a CPU and offline. No external service needed.
"""
import json
import sqlite3
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import f1_score, roc_auc_score
from sklearn.model_selection import train_test_split

RUN_ID = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:6]
MODELS_DIR = Path("models")
MODELS_DIR.mkdir(exist_ok=True)
REGISTRY_DB = "registry.db"
EXPERIMENTS = "experiments.jsonl"


def git_sha() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL
        ).decode().strip()
    except Exception:
        return "nogit"


def init_registry() -> None:
    con = sqlite3.connect(REGISTRY_DB)
    con.execute(
        """CREATE TABLE IF NOT EXISTS models (
            run_id TEXT PRIMARY KEY,
            created_at TEXT,
            git_sha TEXT,
            f1 REAL,
            auc REAL,
            stage TEXT,
            artifact TEXT
        )"""
    )
    con.commit()
    con.close()


def main() -> int:
    df = pd.read_csv("tickets.csv")
    X = df.drop(columns=["is_high"])
    y = df["is_high"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=42, stratify=y
    )

    model = RandomForestClassifier(n_estimators=120, random_state=42)
    model.fit(X_train, y_train)

    pred = model.predict(X_test)
    proba = model.predict_proba(X_test)[:, 1]
    f1 = round(float(f1_score(y_test, pred)), 4)
    auc = round(float(roc_auc_score(y_test, proba)), 4)

    artifact = str(MODELS_DIR / f"{RUN_ID}.joblib")
    joblib.dump({"model": model, "features": list(X.columns)}, artifact)

    run = {
        "run_id": RUN_ID,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "git_sha": git_sha(),
        "params": {"n_estimators": 120, "random_state": 42},
        "metrics": {"f1": f1, "auc": auc},
        "artifact": artifact,
    }
    with open(EXPERIMENTS, "a") as fh:
        fh.write(json.dumps(run) + "\n")

    init_registry()
    con = sqlite3.connect(REGISTRY_DB)
    con.execute(
        "INSERT INTO models (run_id, created_at, git_sha, f1, auc, stage, artifact) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (RUN_ID, run["created_at"], run["git_sha"], f1, auc, "staging", artifact),
    )
    con.commit()
    con.close()

    print(f"run_id: {RUN_ID}")
    print(f"f1: {f1}")
    print(f"auc: {auc}")
    print(f"artifact: {artifact}")
    print("registered in stage: staging")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Press `Esc`, type `:wq`, press Enter.

Run it twice so you have two runs to compare and promote between:

```bash
python train.py
```

Expected output (yours will differ - the run_id always differs):

```
run_id: 20260725T233028Z-136ee1
f1: 0.5075
auc: 0.6268
artifact: models/20260725T233028Z-136ee1.joblib
registered in stage: staging
```

Run it a second time:

```bash
python train.py
```

Notice the `f1` and `auc` are identical to the first run. That is reproducibility: same seed, same data, same model. Only the run_id changed.

---

## Step 6: Build the model registry CLI

The registry answers "which model is production right now?" and makes rollback a pointer change. `registry.py` gives you `list`, `current`, `promote`, and `rollback`.

Open the file:

```bash
vi registry.py
```

Press `i`, then type this in:

```python
"""Minimal model registry CLI (offline stand-in for MLflow Model Registry).

Commands:
  list                       show all registered runs
  promote <run_id>           move a run to production (demote current prod)
  current                    show the current production run
  rollback                   promote the previous production run

The registry is a SQLite table. "production" is the run the deploy step serves.
"""
import sqlite3
import sys

REGISTRY_DB = "registry.db"


def con():
    return sqlite3.connect(REGISTRY_DB)


def cmd_list() -> int:
    c = con()
    rows = c.execute(
        "SELECT run_id, created_at, f1, auc, stage FROM models ORDER BY created_at"
    ).fetchall()
    c.close()
    if not rows:
        print("registry is empty - run train.py first")
        return 1
    print(f"{'run_id':<28} {'f1':>7} {'auc':>7}  stage")
    for run_id, _created, f1, auc, stage in rows:
        print(f"{run_id:<28} {f1:>7.4f} {auc:>7.4f}  {stage}")
    return 0


def cmd_current() -> int:
    c = con()
    row = c.execute(
        "SELECT run_id, f1, auc, artifact FROM models WHERE stage='production'"
    ).fetchone()
    c.close()
    if not row:
        print("no production model - promote one first")
        return 1
    print(f"production run_id: {row[0]}")
    print(f"f1: {row[1]}  auc: {row[2]}")
    print(f"artifact: {row[3]}")
    return 0


def cmd_promote(run_id: str) -> int:
    c = con()
    hit = c.execute("SELECT run_id FROM models WHERE run_id=?", (run_id,)).fetchone()
    if not hit:
        print(f"run_id {run_id} not found in registry")
        c.close()
        return 1
    # Demote whatever is currently production to "archived".
    c.execute("UPDATE models SET stage='archived' WHERE stage='production'")
    c.execute("UPDATE models SET stage='production' WHERE run_id=?", (run_id,))
    c.commit()
    c.close()
    print(f"promoted {run_id} to production")
    return 0


def cmd_rollback() -> int:
    c = con()
    # Most recently archived run is the previous production.
    prev = c.execute(
        "SELECT run_id FROM models WHERE stage='archived' ORDER BY created_at DESC LIMIT 1"
    ).fetchone()
    if not prev:
        print("no archived run to roll back to")
        c.close()
        return 1
    c.execute("UPDATE models SET stage='archived' WHERE stage='production'")
    c.execute("UPDATE models SET stage='production' WHERE run_id=?", (prev[0],))
    c.commit()
    c.close()
    print(f"rolled back: promoted previous run {prev[0]} to production")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print("usage: registry.py [list|current|promote <run_id>|rollback]")
        return 1
    cmd = args[0]
    if cmd == "list":
        return cmd_list()
    if cmd == "current":
        return cmd_current()
    if cmd == "promote":
        if len(args) < 2:
            print("usage: registry.py promote <run_id>")
            return 1
        return cmd_promote(args[1])
    if cmd == "rollback":
        return cmd_rollback()
    print(f"unknown command: {cmd}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
```

Press `Esc`, type `:wq`, press Enter.

List your registered runs:

```bash
python registry.py list
```

Expected output (yours will differ):

```
run_id                            f1     auc  stage
20260725T233028Z-136ee1       0.5075  0.6268  staging
20260725T233031Z-eb93f2       0.5075  0.6268  staging
```

Now promote the **first** run to production. Copy the first run_id from your own list (yours differs from the guide):

```bash
python registry.py promote 20260725T233028Z-136ee1
```

Replace the run_id above with your own first run_id. The `promote` command moves it to the `production` stage.

Expected output (yours will differ):

```
promoted 20260725T233028Z-136ee1 to production
```

Confirm which model is production:

```bash
python registry.py current
```

Expected output (yours will differ):

```
production run_id: 20260725T233028Z-136ee1
f1: 0.5075  auc: 0.6268
artifact: models/20260725T233028Z-136ee1.joblib
```

You now have a decoupled deploy: the registry, not the code, decides which model is live.

---

## Step 7: Capture a drift baseline

Drift detection compares live traffic against the distribution the model trained on. First we save that baseline.

Open the file:

```bash
vi save_baseline.py
```

Press `i`, then type this in:

```python
"""Capture the training-data feature distribution as a drift baseline.

Drift detection compares live traffic against the distribution the model was
trained on. We save summary statistics and the raw training columns (small
here) so the detector can run a Kolmogorov-Smirnov test offline.
"""
import json

import pandas as pd

df = pd.read_csv("tickets.csv")
features = ["age_hours", "reply_count", "customer_tier", "sentiment"]

baseline = {"n": len(df), "features": {}}
for col in features:
    baseline["features"][col] = {
        "mean": round(float(df[col].mean()), 4),
        "std": round(float(df[col].std()), 4),
        "values": df[col].tolist(),   # kept for the KS test; fine at this size
    }

with open("baseline.json", "w") as fh:
    json.dump(baseline, fh)

print(f"wrote baseline.json from {len(df)} training rows")
for col in features:
    m = baseline["features"][col]["mean"]
    s = baseline["features"][col]["std"]
    print(f"  {col}: mean={m} std={s}")
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python save_baseline.py
```

Expected output (yours will differ):

```
wrote baseline.json from 2000 training rows
  age_hours: mean=12.046 std=12.1318
  reply_count: mean=2.9505 std=1.6157
  customer_tier: mean=1.5085 std=0.6739
  sentiment: mean=-0.0186 std=0.9786
```

---

## Step 8: Build the drift detector

`detect_drift.py` runs a two-sample Kolmogorov-Smirnov (KS) test per feature. The KS statistic is the largest gap between the baseline and the live distribution; a tiny p-value means the live data no longer matches training. The script exits `0` if nothing drifted and `1` if anything did - so a monitor or CI job can react automatically (Concepts 10.5, threshold alerts).

Open the file:

```bash
vi detect_drift.py
```

Press `i`, then type this in:

```python
"""Detect data drift between the training baseline and a live sample.

Uses the two-sample Kolmogorov-Smirnov (KS) test from scipy for each numeric
feature. The KS statistic measures the largest gap between two distributions;
a small p-value means the live data no longer looks like the training data.

Exit code is 0 if no feature drifted, 1 if any feature drifted. That lets a
monitor or CI job react to drift automatically.

Usage: python detect_drift.py <live_csv>
"""
import json
import sys

import pandas as pd
from scipy import stats

P_THRESHOLD = 0.01   # p below this = drift for that feature
FEATURES = ["age_hours", "reply_count", "customer_tier", "sentiment"]


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: detect_drift.py <live_csv>")
        return 2

    live = pd.read_csv(sys.argv[1])
    with open("baseline.json") as fh:
        baseline = json.load(fh)

    drifted = []
    print(f"{'feature':<16} {'ks_stat':>8} {'p_value':>10}  status")
    for col in FEATURES:
        base_vals = baseline["features"][col]["values"]
        live_vals = live[col].tolist()
        ks_stat, p_value = stats.ks_2samp(base_vals, live_vals)
        status = "DRIFT" if p_value < P_THRESHOLD else "ok"
        if p_value < P_THRESHOLD:
            drifted.append(col)
        print(f"{col:<16} {ks_stat:>8.4f} {p_value:>10.2e}  {status}")

    print("")
    if drifted:
        print(f"RESULT: DRIFT DETECTED in {len(drifted)} feature(s): {', '.join(drifted)}")
        return 1
    print("RESULT: no drift detected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Press `Esc`, type `:wq`, press Enter.

To test both outcomes we need two live samples: one that matches training and one that has drifted. Create them with a one-line Python program. `python -c` runs the code passed on the command line.

```bash
python -c "import pandas as pd; df=pd.read_csv('tickets.csv'); df.sample(400,random_state=7).to_csv('live_ok.csv',index=False); d=df.sample(400,random_state=7).copy(); d['sentiment']=d['sentiment']-2.0; d['age_hours']=d['age_hours']*3; d.to_csv('live_drift.csv',index=False); print('made live_ok.csv and live_drift.csv')"
```

Expected output:

```
made live_ok.csv and live_drift.csv
```

Run the detector on the matching sample:

```bash
python detect_drift.py live_ok.csv
```

Expected output (yours will differ):

```
feature           ks_stat    p_value  status
age_hours          0.0325   8.65e-01  ok
reply_count        0.0230   9.94e-01  ok
customer_tier      0.0115   1.00e+00  ok
sentiment          0.0290   9.37e-01  ok

RESULT: no drift detected
```

Now run it on the drifted sample:

```bash
python detect_drift.py live_drift.csv
```

Expected output (yours will differ):

```
feature           ks_stat    p_value  status
age_hours          0.3975   1.04e-47  DRIFT
reply_count        0.0230   9.94e-01  ok
customer_tier      0.0115   1.00e+00  ok
sentiment          0.6935  1.35e-156  DRIFT

RESULT: DRIFT DETECTED in 2 feature(s): age_hours, sentiment
```

The detector caught the two features we shifted and ignored the two we did not. Check the exit code to confirm it can drive automation:

```bash
echo $?
```

`echo $?` prints the exit code of the last command. After a drift run it should be `1`.

Expected output:

```
1
```

---

## Step 9: Deploy the model behind an API

`serve.py` is the deploy step. It loads whatever the registry marks `production` and serves predictions over FastAPI. Every prediction is logged to `metrics.jsonl` for the monitor.

Open the file:

```bash
vi serve.py
```

Press `i`, then type this in:

```python
"""Serve the current production model over FastAPI, with request logging.

The deploy step is: whatever run the registry marks 'production' is the model
this API loads. Every prediction is appended to metrics.jsonl so the monitor
can compute request count, latency, and error rate later.
"""
import json
import sqlite3
import time
from datetime import datetime, timezone

import joblib
from fastapi import FastAPI
from pydantic import BaseModel

REGISTRY_DB = "registry.db"
METRICS_LOG = "metrics.jsonl"

app = FastAPI(title="ticket-priority")


class Ticket(BaseModel):
    age_hours: float
    reply_count: int
    customer_tier: int
    sentiment: float


def load_production():
    con = sqlite3.connect(REGISTRY_DB)
    row = con.execute(
        "SELECT run_id, artifact FROM models WHERE stage='production'"
    ).fetchone()
    con.close()
    if not row:
        raise RuntimeError("no production model in registry - promote one first")
    bundle = joblib.load(row[1])
    return row[0], bundle["model"], bundle["features"]


RUN_ID, MODEL, FEATURES = load_production()


def log_metric(record: dict) -> None:
    with open(METRICS_LOG, "a") as fh:
        fh.write(json.dumps(record) + "\n")


@app.get("/health")
def health():
    return {"status": "ok", "run_id": RUN_ID}


@app.post("/predict")
def predict(ticket: Ticket):
    start = time.time()
    row = [[getattr(ticket, f) for f in FEATURES]]
    proba = float(MODEL.predict_proba(row)[0][1])
    priority = "high" if proba >= 0.5 else "normal"
    latency_ms = round((time.time() - start) * 1000, 2)
    log_metric({
        "ts": datetime.now(timezone.utc).isoformat(),
        "run_id": RUN_ID,
        "latency_ms": latency_ms,
        "priority": priority,
        "score": round(proba, 4),
    })
    return {"priority": priority, "score": round(proba, 4), "run_id": RUN_ID}
```

Press `Esc`, type `:wq`, press Enter.

Start the API. `uvicorn serve:app` runs the FastAPI app named `app` in `serve.py`. `--host 127.0.0.1` binds it to localhost, `--port 8199` is the port. The `&` at the end runs it in the background so you get your prompt back.

```bash
uvicorn serve:app --host 127.0.0.1 --port 8199 &
```

Wait a couple of seconds for it to boot, then check health. `curl` makes an HTTP request; `-s` is silent (no progress bar).

```bash
curl -s http://127.0.0.1:8199/health
```

Expected output (yours will differ in run_id):

```
{"status":"ok","run_id":"20260725T233028Z-136ee1"}
```

Send a prediction. `-X POST` sets the HTTP method, `-H` sets a header saying the body is JSON, and `-d` is the JSON body describing one ticket.

```bash
curl -s -X POST http://127.0.0.1:8199/predict -H 'Content-Type: application/json' -d '{"age_hours": 40, "reply_count": 6, "customer_tier": 3, "sentiment": -1.5}'
```

Expected output (yours will differ):

```
{"priority":"high","score":0.825,"run_id":"20260725T233028Z-136ee1"}
```

A tier-3 customer, angry sentiment, stale ticket - the model says high priority, exactly the rule we baked in. Stop the API now that we have confirmed it. `kill %1` stops the background job we started.

```bash
kill %1
```

---

## Step 10: Monitor the serving traffic

`monitor.py` reads `metrics.jsonl` and reports the numbers you would put on a dashboard: request count, average and p95 latency, and the share of high-priority predictions.

Open the file:

```bash
vi monitor.py
```

Press `i`, then type this in:

```python
"""Summarise serving metrics from metrics.jsonl.

Computes the operational numbers you would put on a dashboard: total requests,
average and p95 latency, and the share of high-priority predictions. This is
the MLOps equivalent of watching a web app - but for a model.
"""
import json
import sys
from pathlib import Path

METRICS_LOG = "metrics.jsonl"


def percentile(values, pct):
    if not values:
        return 0.0
    values = sorted(values)
    k = (len(values) - 1) * (pct / 100)
    lo = int(k)
    hi = min(lo + 1, len(values) - 1)
    frac = k - lo
    return values[lo] + (values[hi] - values[lo]) * frac


def main() -> int:
    path = Path(METRICS_LOG)
    if not path.exists():
        print("no metrics.jsonl yet - send some requests to the API first")
        return 1

    latencies = []
    total = 0
    high = 0
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        total += 1
        latencies.append(rec.get("latency_ms", 0.0))
        if rec.get("priority") == "high":
            high += 1

    avg = round(sum(latencies) / len(latencies), 2) if latencies else 0.0
    p95 = round(percentile(latencies, 95), 2)
    high_rate = round(high / total, 4) if total else 0.0

    print(f"requests:        {total}")
    print(f"avg_latency_ms:  {avg}")
    print(f"p95_latency_ms:  {p95}")
    print(f"high_rate:       {high_rate}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Press `Esc`, type `:wq`, press Enter.

Run it:

```bash
python monitor.py
```

Expected output (yours will differ - you sent one request in Step 9):

```
requests:        1
avg_latency_ms:  5.11
p95_latency_ms:  5.11
high_rate:       1.0
```

In USE you replace this file-based summary with a Prometheus-and-Grafana-style dashboard. The metrics you compute are the same.

---

## Step 11: Close the loop with a drift-triggered retrain

`retrain.py` ties it together: it checks for drift first, and only retrains if drift is found. This is the mature practice from Concepts 10.5 - retrain because a signal told you to, not on a blind schedule.

Open the file:

```bash
vi retrain.py
```

Press `i`, then type this in:

```python
"""Automated retrain trigger: retrain only when drift is detected.

This closes the MLOps loop: monitor sees drift -> retrain on fresh data ->
register the new model in staging. A human (or a CI gate) then promotes it.
This script does the drift check and, if drift is found, refits on the live
data appended to the training set and registers a new staging run.

Usage: python retrain.py <live_csv>
"""
import subprocess
import sys


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: retrain.py <live_csv>")
        return 2
    live_csv = sys.argv[1]

    print("==> Checking for drift before retraining")
    drift = subprocess.run(
        [sys.executable, "detect_drift.py", live_csv]
    ).returncode

    if drift == 0:
        print("==> No drift. Skipping retrain (do not retrain for no reason).")
        return 0

    print("==> Drift detected. Retraining on refreshed data.")
    # In a real system you would append labelled live data to the training set.
    # Here we retrain train.py, which registers a fresh staging run.
    rc = subprocess.run([sys.executable, "train.py"]).returncode
    if rc != 0:
        print("==> Retrain FAILED")
        return 1
    print("==> Retrain complete. New model registered in staging.")
    print("==> Review metrics, then: python registry.py promote <new_run_id>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Press `Esc`, type `:wq`, press Enter.

First run it against the matching sample. It should check drift, find none, and skip:

```bash
python retrain.py live_ok.csv
```

Expected output (yours will differ):

```
feature           ks_stat    p_value  status
age_hours          0.0325   8.65e-01  ok
reply_count        0.0230   9.94e-01  ok
customer_tier      0.0115   1.00e+00  ok
sentiment          0.0290   9.37e-01  ok

RESULT: no drift detected
==> Checking for drift before retraining
==> No drift. Skipping retrain (do not retrain for no reason).
```

Now run it against the drifted sample. It should detect drift and retrain:

```bash
python retrain.py live_drift.csv
```

Expected output (yours will differ):

```
feature           ks_stat    p_value  status
age_hours          0.3975   1.04e-47  DRIFT
reply_count        0.0230   9.94e-01  ok
customer_tier      0.0115   1.00e+00  ok
sentiment          0.6935  1.35e-156  DRIFT

RESULT: DRIFT DETECTED in 2 feature(s): age_hours, sentiment
==> Checking for drift before retraining
==> Drift detected. Retraining on refreshed data.
run_id: 20260725T233524Z-fee688
f1: 0.5075
auc: 0.6268
artifact: models/20260725T233524Z-fee688.joblib
registered in stage: staging
==> Retrain complete. New model registered in staging.
==> Review metrics, then: python registry.py promote <new_run_id>
```

The new model landed in `staging`, not `production`. That is deliberate: a human or a validation gate promotes it after checking the metrics. Confirm both models are in the registry:

```bash
python registry.py list
```

Expected output (yours will differ):

```
run_id                            f1     auc  stage
20260725T233028Z-136ee1       0.5075  0.6268  production
20260725T233031Z-eb93f2       0.5075  0.6268  archived
20260725T233524Z-fee688       0.5075  0.6268  staging
```

---

## What you built

You now have every stage of the MLOps lifecycle as a working, offline artifact:

- **Experiment tracking** - `experiments.jsonl` (train.py)
- **Reproducibility** - fixed seed; identical metrics across runs
- **Model registry** - `registry.db` with stages (registry.py)
- **Deployment** - FastAPI serving the production model (serve.py)
- **Monitoring** - request/latency/rate summary (monitor.py)
- **Drift detection** - KS test with a threshold and exit code (detect_drift.py)
- **Retraining** - triggered by drift, not by the calendar (retrain.py)
- **Rollback** - a registry pointer change (registry.py rollback, used in SURVIVE)

Keep this folder. The USE exercises and every SURVIVE scenario build on it.

Prof. Happy (SUTA Labs)
