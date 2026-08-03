# BUILD: Project 13 - Deploy One AI App to Three Targets

**Tier 13 - the cloud-platforms capstone.** You will take ONE controlled AI application and make it deployable to three targets: Local Docker, AWS, and a second cloud (Google Cloud / Vertex). Then you produce the deliverable a client actually pays for: a comparison of the targets on Cost, Security, Complexity, Deployment time, Observability, Vendor lock-in, Data residency, and Operational support. This is exactly what a consultant hands a client who asks "where should we run this, and what do we give up either way?"

**Validated on:** CentOS Stream 9, Python 3.12, Docker. All output shown is real (truncated where long; timings and token counts will differ on your machine).

**Prerequisite:** you read Concepts 13.1-13.3. You do not need any prior cloud code.

**Cloud accounts - read this first.** Real cloud calls need credentials that YOU supply through environment variables (`AWS_ACCESS_KEY_ID` and friends for AWS; `GOOGLE_APPLICATION_CREDENTIALS` and `GCP_PROJECT` for GCP). This project is written so it **runs and is fully demonstrable with NO cloud account at all**, using a built-in LOCAL MOCK cloud. The mock is deterministic and free. When (and only when) you want to deploy to a real cloud, you set the matching credentials and the app picks the target up automatically. Every step below tells you clearly whether it needs a real cloud account. Steps marked **[REAL CLOUD]** need one; every other step runs for free on the mock.

**What you build:** a folder `project13-cloud/` with one portable app (`cloud_ai.py`), a tiny HTTP wrapper (`app.py`), a single `Dockerfile` that deploys to all three targets, and a comparison script that emits your deliverable table. You run the whole thing locally first, then optionally point it at a real cloud.

---

## Step 1: Create the project folder

On your **lab server** (CentOS Stream 9), as **ec2-user**, make a working folder:

```bash
mkdir -p ~/project13-cloud
```

`mkdir -p` creates the folder (`-p` means "do not error if it already exists"). Move into it:

```bash
cd ~/project13-cloud
```

`cd` changes into the folder so every file we create lands here.

---

## Step 2: Create and activate a virtual environment

A virtual environment keeps this project's packages separate from the system Python.

Still on your **lab server**, as **ec2-user**, in `~/project13-cloud`:

```bash
python3.12 -m venv .venv
```

`-m venv` runs Python's built-in venv module; `.venv` is the folder it creates. Activate it:

```bash
source .venv/bin/activate
```

`source` runs the activate script in your current shell. Your prompt now shows `(.venv)` at the front, which means the environment is on.

---

## Step 3: Write the portable app (the anti-lock-in core)

This is the heart of the design from Concepts 13.1-13.3: every model call goes through ONE function, `complete()`, which routes to the chosen target - local mock, AWS Bedrock, or GCP Vertex - and **degrades gracefully to the local mock on any failure**. Because the whole app depends only on `complete()`, the same code runs on every target, and moving clouds is a one-setting change, not a rewrite.

Still on your **lab server**, as **ec2-user**, in `~/project13-cloud`, open a new file with vi:

```bash
vi cloud_ai.py
```

Press `i` to enter insert mode, then type (or paste) the following. Read the comments as you go.

```python
#!/usr/bin/env python3
"""Portable cloud-AI application (Tier 13 Project 13).

ONE application, THREE deployment targets: local (mock), AWS Bedrock, and a
second cloud (GCP Vertex). Every model call goes through a single provider
abstraction so the SAME code runs on every target - the anti-lock-in design.

Real cloud calls need YOUR credentials in env vars:
  - AWS:   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, BEDROCK_MODEL_ID
  - GCP:   GOOGLE_APPLICATION_CREDENTIALS (path), GCP_PROJECT, GCP_REGION
When those are absent (the default), the app DEGRADES GRACEFULLY to a LOCAL
MOCK cloud so BUILD/USE/SURVIVE are demonstrable and testable for free.

Choose the target with CLOUD_TARGET=local|aws|gcp (default: local).
"""
import json
import os
import sys
import time


def _mock_complete(target_label: str, prompt: str) -> dict:
    """Local mock stand-in for a cloud model. Deterministic, free, offline."""
    text = json.dumps({"category": "billing", "urgency": "high"})
    return {
        "target": target_label,
        "backend": "mock",
        "text": text,
        "input_tokens": max(1, len(prompt) // 4),
        "output_tokens": max(1, len(text) // 4),
    }


def _aws_complete(prompt: str) -> dict:
    """Call AWS Bedrock. Requires real AWS creds; else raises to trigger fallback."""
    region = os.environ.get("AWS_REGION")
    model_id = os.environ.get("BEDROCK_MODEL_ID")
    if not (os.environ.get("AWS_ACCESS_KEY_ID") and region and model_id):
        raise RuntimeError(
            "AWS not configured. Set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, "
            "AWS_REGION and BEDROCK_MODEL_ID to call real Bedrock."
        )
    import boto3  # imported lazily so the app runs with no AWS SDK installed
    client = boto3.client("bedrock-runtime", region_name=region)
    resp = client.converse(
        modelId=model_id,
        messages=[{"role": "user", "content": [{"text": prompt}]}],
    )
    text = resp["output"]["message"]["content"][0]["text"]
    usage = resp.get("usage", {})
    return {
        "target": "aws",
        "backend": "bedrock",
        "text": text,
        "input_tokens": usage.get("inputTokens", 0),
        "output_tokens": usage.get("outputTokens", 0),
    }


def _gcp_complete(prompt: str) -> dict:
    """Call GCP Vertex. Requires real GCP creds; else raises to trigger fallback."""
    project = os.environ.get("GCP_PROJECT")
    if not (os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") and project):
        raise RuntimeError(
            "GCP not configured. Set GOOGLE_APPLICATION_CREDENTIALS and GCP_PROJECT "
            "to call real Vertex AI."
        )
    import vertexai  # lazy import
    from vertexai.generative_models import GenerativeModel
    vertexai.init(project=project, location=os.environ.get("GCP_REGION", "us-central1"))
    model = GenerativeModel(os.environ.get("VERTEX_MODEL_ID", "gemini-1.5-flash"))
    resp = model.generate_content(prompt)
    return {
        "target": "gcp",
        "backend": "vertex",
        "text": resp.text,
        "input_tokens": 0,
        "output_tokens": 0,
    }


def complete(prompt: str) -> dict:
    """Route to the chosen target; on ANY failure, degrade to the local mock.

    Graceful degradation: a missing credential or a cloud error never takes the
    feature down - it falls back to the mock and logs WHY (never silent).
    """
    target = os.environ.get("CLOUD_TARGET", "local").lower()
    start = time.time()
    try:
        if target == "aws":
            result = _aws_complete(prompt)
        elif target == "gcp":
            result = _gcp_complete(prompt)
        else:
            result = _mock_complete("local", prompt)
    except Exception as exc:
        print(f"[warn] target '{target}' unavailable ({exc}); using local mock",
              file=sys.stderr)
        result = _mock_complete(target, prompt)
    result["latency_ms"] = round((time.time() - start) * 1000, 1)
    return result


if __name__ == "__main__":
    prompt = "Classify: I was double charged and need a refund today. Urgent."
    out = complete(prompt)
    print("RESULT " + json.dumps(out))
```

Press `Esc` to leave insert mode, then type `:wq` and press Enter to save and quit vi.

Run it once to prove the local mock works with no cloud account:

```bash
python cloud_ai.py
```

`python` runs the file; the `__main__` block sends a sample ticket through `complete()`.

Expected output (yours will differ):

```
RESULT {"target": "local", "backend": "mock", "text": "{\"category\": \"billing\", \"urgency\": \"high\"}", "input_tokens": 15, "output_tokens": 10, "latency_ms": 0.0}
```

Now prove graceful degradation: ask for the AWS target with NO AWS credentials set. It must warn and fall back, not crash:

```bash
CLOUD_TARGET=aws python cloud_ai.py
```

`CLOUD_TARGET=aws` sets the env var for this one command only.

Expected output (yours will differ):

```
[warn] target 'aws' unavailable (AWS not configured. Set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION and BEDROCK_MODEL_ID to call real Bedrock.); using local mock
RESULT {"target": "aws", "backend": "mock", "text": "{\"category\": \"billing\", \"urgency\": \"high\"}", "input_tokens": 15, "output_tokens": 10, "latency_ms": 0.0}
```

The app tried AWS, found no credentials, told you exactly what to set, and kept working on the mock. That is graceful degradation.

---

## Step 4: Write the HTTP wrapper

A real deployment is a service, not a script. This tiny wrapper exposes the app over HTTP, using only the standard library so the mock path needs nothing installed. The SAME wrapper serves every target - the target is chosen by `CLOUD_TARGET`.

Still on your **lab server**, as **ec2-user**, in `~/project13-cloud`, open a new file:

```bash
vi app.py
```

Press `i`, then enter the following:

```python
#!/usr/bin/env python3
"""Tiny HTTP wrapper around cloud_ai.complete, stdlib only.

GET /health  -> {"status": "ok", "target": "<target>"}
POST /triage -> {"prompt": "..."} returns the model result JSON.

The SAME container image deploys to every target - CLOUD_TARGET picks the cloud.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

from cloud_ai import complete

PORT = int(os.environ.get("PORT", "8080"))
TARGET = os.environ.get("CLOUD_TARGET", "local")


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok", "target": TARGET})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/triage":
            self._send(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid JSON"})
            return
        self._send(200, complete(data.get("prompt", "")))

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"serving on :{PORT} target={TARGET}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
```

Press `Esc`, type `:wq`, press Enter.

Start the server in the background so you keep your prompt:

```bash
python app.py &
```

The trailing `&` runs it in the background. Wait a second, then check health:

```bash
curl -s http://127.0.0.1:8080/health
```

`curl -s` makes a quiet HTTP request.

Expected output (yours will differ):

```
{"status": "ok", "target": "local"}
```

Send a ticket to the triage endpoint:

```bash
curl -s -X POST http://127.0.0.1:8080/triage -d '{"prompt":"double charged, refund now"}'
```

`-X POST` sends a POST request; `-d` supplies the JSON body.

Expected output (yours will differ):

```
{"target": "local", "backend": "mock", "text": "{\"category\": \"billing\", \"urgency\": \"high\"}", "input_tokens": 6, "output_tokens": 10, "latency_ms": 0.0}
```

Stop the background server before moving on:

```bash
kill %1
```

`kill %1` stops the first background job (the server).

---

## Step 5: Write the Dockerfile (this is the LOCAL DOCKER target)

One image, three targets. The image runs the mock by default and needs no cloud account. It also installs the AWS and GCP SDKs so a REAL cloud call works when you set credentials, but those are imported lazily, so the mock never requires them.

Still on your **lab server**, as **ec2-user**, in `~/project13-cloud`, create the requirements file:

```bash
vi requirements.txt
```

Press `i`, enter:

```
# Optional real-cloud SDKs. The app runs on the mock with NEITHER installed,
# because both are imported lazily only when a real cloud target is chosen.
boto3>=1.34
google-cloud-aiplatform>=1.60
```

Press `Esc`, type `:wq`, press Enter. Now the Dockerfile:

```bash
vi Dockerfile
```

Press `i`, enter:

```dockerfile
# One image, three deployment targets. The target is chosen at runtime by the
# CLOUD_TARGET env var, so the SAME image runs on local Docker, AWS, and GCP.
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY cloud_ai.py app.py ./

ENV PORT=8080
ENV CLOUD_TARGET=local
EXPOSE 8080

CMD ["python", "app.py"]
```

Press `Esc`, type `:wq`, press Enter. Build the image:

```bash
docker build -t cloud-ai-p13 .
```

`docker build` builds an image; `-t cloud-ai-p13` names it; the `.` means "use the Dockerfile in this folder". This downloads the base image and SDKs the first time, so it takes a minute or two.

Expected output (yours will differ):

```
...
 => naming to docker.io/library/cloud-ai-p13:latest
```

Run the container, mapping host port 8081 to the container's 8080:

```bash
docker run -d --name p13 -p 8081:8080 -e CLOUD_TARGET=local cloud-ai-p13
```

`-d` runs it in the background; `--name p13` names it; `-p 8081:8080` maps the ports; `-e CLOUD_TARGET=local` selects the local target. Wait a second, then check it:

```bash
curl -s http://127.0.0.1:8081/health
```

Expected output (yours will differ):

```
{"status": "ok", "target": "local"}
```

Send a ticket through the containerized app:

```bash
curl -s -X POST http://127.0.0.1:8081/triage -d '{"prompt":"double charged, refund now"}'
```

Expected output (yours will differ):

```
{"target": "local", "backend": "mock", "text": "{\"category\": \"billing\", \"urgency\": \"high\"}", "input_tokens": 6, "output_tokens": 10, "latency_ms": 0.0}
```

That is your **Local Docker** deployment target, working end to end. Stop and remove the container so it does not hold the port:

```bash
docker rm -f p13
```

`docker rm -f` force-removes the running container.

---

## Step 6: [REAL CLOUD] Deploy the AWS target (optional)

**This step needs a real AWS account with Bedrock enabled.** If you do not have one, skip to Step 8 - your comparison still completes on the mock. When you are ready, this is the shape of the AWS deployment.

First, in the AWS console, request model access in Bedrock for at least one model (for example an Anthropic Claude model) in your region. New accounts have nothing enabled (Concepts 13.1). Note the exact model id.

Still on your **lab server**, as **ec2-user**, export your credentials and target (never hardcode them - Concepts 13.1, Secrets Manager is the production answer):

```bash
export AWS_ACCESS_KEY_ID="your-key-id"
```

```bash
export AWS_SECRET_ACCESS_KEY="your-secret"
```

```bash
export AWS_REGION="us-east-1"
```

```bash
export BEDROCK_MODEL_ID="the-model-id-you-enabled"
```

```bash
export CLOUD_TARGET="aws"
```

Each `export` sets one environment variable for this shell. Now run the same app against real Bedrock:

```bash
python cloud_ai.py
```

If your credentials and model access are correct, you will see `"backend": "bedrock"` and a real model response instead of the mock. If you see the `[warn] ... using local mock` line, one of the four AWS variables is missing or the model is not enabled - the app is telling you exactly what to fix, and it kept running.

For a full managed deployment (ECS/Fargate behind API Gateway, IAM role instead of keys, VPC endpoint, Guardrail, CloudWatch alarms), follow the reference architecture in Concepts 13.1. The container image you built in Step 5 is the artifact you push to Amazon ECR and run on Fargate - no code change.

When done, unset the AWS target so later steps use the mock again:

```bash
unset CLOUD_TARGET
```

---

## Step 7: [REAL CLOUD] Deploy the second cloud - GCP Vertex (optional)

**This step needs a real Google Cloud project with Vertex AI enabled.** Skip if you do not have one. The pattern mirrors AWS - same app, different credentials.

Still on your **lab server**, as **ec2-user**, point the app at GCP:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/home/ec2-user/gcp-service-account.json"
```

```bash
export GCP_PROJECT="your-gcp-project-id"
```

```bash
export GCP_REGION="us-central1"
```

```bash
export CLOUD_TARGET="gcp"
```

`GOOGLE_APPLICATION_CREDENTIALS` points to a service-account key file YOU download from GCP (Concepts 13.3 - a service account is the assumable identity; in production you would use workload identity, not a key file). Run the same app:

```bash
python cloud_ai.py
```

Correct setup shows `"backend": "vertex"` and a real Gemini response. A missing variable produces the `[warn] ... using local mock` line and keeps running.

Unset the target when done:

```bash
unset CLOUD_TARGET
```

The point Project 13 proves: the SAME `cloud_ai.py`, `app.py`, and `Dockerfile` deployed to all three targets. You changed environment variables, never code. That is portability, and it is what keeps a client out of lock-in.

---

## Step 8: Produce the comparison deliverable

Now the consultant output: a table comparing the three targets on the dimensions the plan requires. The functional check runs against the mock for every target, so you produce a complete table for free; the qualitative scores are your assessment to edit per client.

Still on your **lab server**, as **ec2-user**, in `~/project13-cloud`, open a new file:

```bash
vi compare_deployments.py
```

Press `i`, enter:

```python
#!/usr/bin/env python3
"""Project 13 deliverable: compare the SAME app across deployment targets.

For each target it (1) confirms the app answers correctly and (2) records the
comparison dimensions from the plan: Cost, Security, Complexity, Deployment
time, Observability, Vendor lock-in, Data residency, Operational support.

The functional check runs against the LOCAL MOCK for every target (no cloud
account needed). The qualitative scores are the consultant's assessment - edit
them for your real client. Prints a Markdown table for your deliverable.
"""
import json
import os

from cloud_ai import complete

TARGETS = ["local", "aws", "gcp"]

# Consultant assessment per target (1 = worst, 5 = best as framed). Defaults for
# a typical mid-size client; adjust per engagement.
ASSESSMENT = {
    "local":  {"Cost": 5, "Security": 2, "Complexity": 5, "DeployTimeMin": 2,
               "Observability": 1, "LockIn": 5, "DataResidency": 5, "OpsSupport": 1},
    "aws":    {"Cost": 3, "Security": 4, "Complexity": 3, "DeployTimeMin": 45,
               "Observability": 5, "LockIn": 2, "DataResidency": 4, "OpsSupport": 5},
    "gcp":    {"Cost": 3, "Security": 4, "Complexity": 3, "DeployTimeMin": 40,
               "Observability": 4, "LockIn": 2, "DataResidency": 4, "OpsSupport": 4},
}

PROMPT = "Classify: I was double charged and need a refund today. Urgent."


def functional_check(target: str) -> bool:
    """Run the app against a target and confirm it returns valid triage JSON."""
    os.environ["CLOUD_TARGET"] = target
    result = complete(PROMPT)
    try:
        parsed = json.loads(result["text"])
        return parsed.get("category") == "billing"
    except (json.JSONDecodeError, KeyError):
        return False


def main() -> None:
    rows = [(t, functional_check(t), ASSESSMENT[t]) for t in TARGETS]

    print("# Deployment Comparison - Project 13\n")
    print("Functional check runs against the local mock for every target (free).")
    print("Scores are the consultant's 1-5 assessment; DeployTime is in minutes.\n")
    print("| Target | Works | Cost | Security | Complexity | DeployTime(min) "
          "| Observability | LockIn(higher=freer) | DataResidency | OpsSupport |")
    print("|" + "---|" * 10)
    for t, ok, a in rows:
        works = "yes" if ok else "NO"
        print(f"| {t} | {works} | {a['Cost']} | {a['Security']} | {a['Complexity']} "
              f"| {a['DeployTimeMin']} | {a['Observability']} | {a['LockIn']} "
              f"| {a['DataResidency']} | {a['OpsSupport']} |")

    print("\n## Recommendation (edit per client)\n")
    print("- Local Docker: fastest, cheapest, most private, but no managed ops or "
          "observability - development and air-gapped pilots only.")
    print("- AWS (Bedrock): strongest observability and operational support - the "
          "default primary for most enterprise clients.")
    print("- GCP (Vertex): close second; prefer when data gravity is in BigQuery.")
    print("\nEvery model call goes through one abstraction, so the client can move "
          "between targets without a rewrite - lock-in stays low by design.")


if __name__ == "__main__":
    main()
```

Press `Esc`, type `:wq`, press Enter. Generate the deliverable:

```bash
python compare_deployments.py
```

Expected output (yours will differ):

```
# Deployment Comparison - Project 13

Functional check runs against the local mock for every target (free).
Scores are the consultant's 1-5 assessment; DeployTime is in minutes.

| Target | Works | Cost | Security | Complexity | DeployTime(min) | Observability | LockIn(higher=freer) | DataResidency | OpsSupport |
|---|---|---|---|---|---|---|---|---|---|
| local | yes | 5 | 2 | 5 | 2 | 1 | 5 | 5 | 1 |
| aws | yes | 3 | 4 | 3 | 45 | 5 | 2 | 4 | 5 |
| gcp | yes | 3 | 4 | 3 | 40 | 4 | 2 | 4 | 4 |
...
```

Save it to a file you can hand over:

```bash
python compare_deployments.py > deployment-comparison.md
```

`>` redirects the output into a file. Open `deployment-comparison.md`, replace the default scores with your real assessment for a specific client, and you have the Project 13 deliverable.

---

## What you built

- One portable app (`cloud_ai.py`) whose every model call goes through one abstraction, deployable to local, AWS, and GCP by changing only environment variables.
- A single container image (`Dockerfile`) that is the artifact for all three targets.
- A working Local Docker deployment, plus the exact steps and env vars for real AWS Bedrock and GCP Vertex.
- The consultant deliverable: a comparison of the three targets on cost, security, complexity, deploy time, observability, lock-in, data residency, and operational support.

The lesson under all of it: portability is a design choice you make on day one. Put every model call behind one interface, keep credentials in env vars, and the client can move clouds in days - which is exactly the freedom they are paying you to protect.

---

Prof. Happy (SUTA Labs)
