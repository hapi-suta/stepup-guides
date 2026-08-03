# USE: MLOps and LLMOps reinforcement exercises

**Tier 10 - MLOps and LLMOps (ai-consulting track).** These exercises reinforce the BUILD pipeline on new problems and produce the operational artifacts the plan requires. Do them after you finish `build/01-mlops-pipeline.md`, in the same `~/mlops-pipeline` folder with the venv activated.

The plan lists two USE deliverables for this tier:

1. Add prompt regression tests to CI so a prompt change cannot ship if it fails the golden set.
2. Wire Prometheus and Grafana dashboards for tokens, cost, latency, and groundedness.

Each exercise below builds toward those. Everything runs offline on a CPU. The LLM client reads its key from the environment and falls back to a deterministic mock, so you never need a network connection or a paid key to complete the tier.

Before you start, make sure you are set up. On your **lab server** (CentOS Stream 9), as **ec2-user**:

```bash
cd ~/mlops-pipeline
```

`cd` moves you into the project folder from BUILD.

```bash
source .venv/bin/activate
```

`source` activates the virtual environment so `python` and `pip` use the isolated setup.

---

## Exercise 1: An offline LLM client with a mock fallback

Every LLMOps exercise needs a way to call a model. To keep the labs runnable offline, we build a client that uses a real API only if a key is present, and a deterministic mock otherwise.

Open the file:

```bash
vi llm_client.py
```

Press `i` to enter insert mode, then type this in:

```python
"""A tiny LLM client that reads its API key from the environment and falls
back to a deterministic MOCK when no key is set.

This lets every LLMOps lab run offline. If LLM_API_KEY is present the real
call path is taken (provider-agnostic and minimal); if not, the mock returns a
canned, deterministic answer so tests are reproducible.

The mock also OBEYS common prompt instructions ("one word", "brief") by
truncating its answer, so a badly worded prompt template actually degrades the
answer and the golden set can catch it - all without a network call.
"""
import hashlib
import os


def _base_answer(prompt: str) -> str:
    p = prompt.lower()
    if "capital of france" in p:
        return "The capital of France is Paris."
    if "refund" in p and "policy" in p:
        return "Refunds are available within 30 days of purchase with a receipt."
    if "reset" in p and "password" in p:
        return "To reset your password, click 'Forgot password' on the login page."
    h = hashlib.sha256(prompt.encode()).hexdigest()[:8]
    return f"MOCK_RESPONSE[{h}]"


def _apply_prompt_instructions(prompt: str, answer: str) -> str:
    """Simulate the model obeying formatting instructions in the prompt."""
    p = prompt.lower()
    if "one word" in p or "single word" in p:
        return answer.split()[0] if answer.split() else answer
    if "brief" in p or "one sentence" in p or "short" in p or "concise" in p:
        return " ".join(answer.split()[:4])
    return answer


def _mock_answer(prompt: str) -> str:
    return _apply_prompt_instructions(prompt, _base_answer(prompt))


def complete(prompt: str, system: str = "") -> str:
    """Return a completion. Real path if LLM_API_KEY is set, else mock."""
    api_key = os.environ.get("LLM_API_KEY", "").strip()
    if not api_key:
        return _mock_answer(prompt)

    try:
        import json
        import urllib.request

        model = os.environ.get("LLM_MODEL", "claude-sonnet-4-6")
        url = os.environ.get("LLM_API_URL", "https://api.anthropic.com/v1/messages")
        body = json.dumps({
            "model": model,
            "max_tokens": 256,
            "system": system,
            "messages": [{"role": "user", "content": prompt}],
        }).encode()
        req = urllib.request.Request(url, data=body, method="POST")
        req.add_header("content-type", "application/json")
        req.add_header("x-api-key", api_key)
        req.add_header("anthropic-version", "2023-06-01")
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
        return data["content"][0]["text"]
    except Exception as exc:
        print(f"[llm_client] real call failed ({exc}); using mock")
        return _mock_answer(prompt)


if __name__ == "__main__":
    print(complete("What is the capital of France?"))
    print(complete("Answer in one word only. What is the refund policy?"))
```

Press `Esc`, type `:wq`, press Enter.

Run it to see both the normal answer and a truncated one:

```bash
python llm_client.py
```

Expected output (yours will differ):

```
The capital of France is Paris.
Refunds
```

The second line is short because the prompt said "one word only" - the mock obeyed the instruction. That is what makes the prompt regression exercise meaningful offline.

Note on keys: to use a real model instead of the mock, set `LLM_API_KEY` in your shell (`export LLM_API_KEY=...`) before running. Never hardcode the key in the file. Without the variable the mock is used automatically.

---

## Exercise 2: A prompt regression test and its golden set

This is the first plan deliverable. A prompt regression test runs a golden set of questions through the current prompt template and fails if any answer is missing its required content.

Create the golden set. Open the file:

```bash
vi golden.json
```

Press `i`, then type this in:

```json
[
  {"prompt": "What is the capital of France?", "must_include": ["Paris"]},
  {"prompt": "What is the refund policy?", "must_include": ["30 days", "receipt"]},
  {"prompt": "How do I reset my password?", "must_include": ["Forgot password", "login"]}
]
```

Press `Esc`, type `:wq`, press Enter.

Now the regression test. Open the file:

```bash
vi prompt_regression.py
```

Press `i`, then type this in:

```python
"""Prompt regression test against a golden dataset.

Each golden case has a prompt and a list of strings the answer MUST contain.
We render the prompt through the current prompt template, call the LLM (mock by
default), and check the answer contains every required string. Exit 0 if all
pass, 1 if any fail - so CI can block a bad prompt from shipping.
"""
import json
import sys
from pathlib import Path

from llm_client import complete

TEMPLATE_FILE = "prompt_template.txt"
GOLDEN_FILE = "golden.json"


def load_template() -> str:
    p = Path(TEMPLATE_FILE)
    if p.exists():
        return p.read_text()
    return "{question}"   # default: pass the question straight through


def main() -> int:
    template = load_template()
    golden = json.loads(Path(GOLDEN_FILE).read_text())

    failures = 0
    for case in golden:
        prompt = template.replace("{question}", case["prompt"])
        answer = complete(prompt)
        missing = [s for s in case["must_include"] if s.lower() not in answer.lower()]
        if missing:
            failures += 1
            print(f"FAIL: {case['prompt']!r}")
            print(f"      missing: {missing}")
            print(f"      got: {answer!r}")
        else:
            print(f"PASS: {case['prompt']!r}")

    print("")
    if failures:
        print(f"RESULT: FAIL - {failures} of {len(golden)} golden cases failed")
        return 1
    print(f"RESULT: PASS - all {len(golden)} golden cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Press `Esc`, type `:wq`, press Enter.

Run it. With no `prompt_template.txt`, the default template passes the question straight through and every case passes:

```bash
python prompt_regression.py
```

Expected output (yours will differ):

```
PASS: 'What is the capital of France?'
PASS: 'What is the refund policy?'
PASS: 'How do I reset my password?'

RESULT: PASS - all 3 golden cases passed
```

Now prove it catches a bad prompt. Write a template that forces one-word answers - which will break every case. `printf` writes text to a file without a trailing newline; the `>` redirects it into the file.

```bash
printf 'Answer in one word only. {question}' > prompt_template.txt
```

Run the test again:

```bash
python prompt_regression.py
```

Expected output (yours will differ):

```
FAIL: 'What is the capital of France?'
      missing: ['Paris']
      got: 'The'
FAIL: 'What is the refund policy?'
      missing: ['30 days', 'receipt']
      got: 'Refunds'
FAIL: 'How do I reset my password?'
      missing: ['Forgot password', 'login']
      got: 'To'

RESULT: FAIL - 3 of 3 golden cases failed
```

The regression test failed and returned a non-zero exit code. Remove the bad template so your project is clean again:

```bash
rm -f prompt_template.txt
```

---

## Exercise 3: Wire the regression test into CI

The plan deliverable is that a prompt change **cannot ship** if it fails the golden set. That is a CI gate. GitHub Actions runs your test on every push; a non-zero exit blocks the merge.

Create the workflow directory. `mkdir -p` makes the nested folders GitHub Actions expects.

```bash
mkdir -p .github/workflows
```

Open the workflow file:

```bash
vi .github/workflows/prompt-regression.yml
```

Press `i`, then type this in:

```yaml
name: prompt-regression

# Run on every push and pull request so a bad prompt cannot merge.
on: [push, pull_request]

jobs:
  golden-set:
    runs-on: ubuntu-latest
    steps:
      - name: Check out the code
        uses: actions/checkout@v4

      - name: Set up Python 3.12
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Install dependencies
        run: pip install scikit-learn pandas numpy scipy joblib

      - name: Run prompt regression against the golden set
        run: python prompt_regression.py
```

Press `Esc`, type `:wq`, press Enter.

The key line is the last `run`. When `prompt_regression.py` exits non-zero (a golden case failed), GitHub Actions marks the job failed and blocks the merge. That is the gate the proof of competence requires. Confirm the file is valid text:

```bash
cat .github/workflows/prompt-regression.yml
```

`cat` prints the file so you can visually confirm it saved correctly.

Expected output (the file you just wrote):

```
name: prompt-regression
...
      - name: Run prompt regression against the golden set
        run: python prompt_regression.py
```

To simulate what CI does locally, run the test and check its exit code. `&&` runs the second command only if the first succeeded.

```bash
python prompt_regression.py && echo "CI GATE: would ship" || echo "CI GATE: blocked"
```

Expected output (yours will differ):

```
PASS: 'What is the capital of France?'
...
RESULT: PASS - all 3 golden cases passed
CI GATE: would ship
```

---

## Exercise 4: Log LLM cost and tokens per request

Before you can dashboard cost, you must record it. This logger writes tokens, cost, and latency per call to `llm_metrics.jsonl`.

Open the file:

```bash
vi llm_serve_log.py
```

Press `i`, then type this in:

```python
"""Simulate LLM serving and log LLMOps metrics per request.

For a normal web app you monitor latency and errors. For an LLM app you also
monitor TOKENS and COST, because those drive the bill and the risk. This
writes one JSON line per call to llm_metrics.jsonl.

Usage: python llm_serve_log.py "<question>" [--calls N]
"""
import argparse
import json
import time
from datetime import datetime, timezone

from llm_client import complete

LOG = "llm_metrics.jsonl"

# Rough public per-token prices (USD). Real numbers change; these are for the
# lab's cost math only.
PRICE_PER_1K_INPUT = 0.003
PRICE_PER_1K_OUTPUT = 0.015


def count_tokens(text: str) -> int:
    """Cheap token estimate: ~4 characters per token. Good enough for a lab."""
    return max(1, len(text) // 4)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("question")
    ap.add_argument("--calls", type=int, default=1)
    args = ap.parse_args()

    for _ in range(args.calls):
        start = time.time()
        answer = complete(args.question)
        latency_ms = round((time.time() - start) * 1000, 2)
        in_tok = count_tokens(args.question)
        out_tok = count_tokens(answer)
        cost = round(
            in_tok / 1000 * PRICE_PER_1K_INPUT
            + out_tok / 1000 * PRICE_PER_1K_OUTPUT,
            6,
        )
        rec = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "latency_ms": latency_ms,
            "input_tokens": in_tok,
            "output_tokens": out_tok,
            "cost_usd": cost,
            "error": False,
        }
        with open(LOG, "a") as fh:
            fh.write(json.dumps(rec) + "\n")

    print(f"logged {args.calls} call(s) to {LOG}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

Press `Esc`, type `:wq`, press Enter.

Log three calls:

```bash
python llm_serve_log.py "What is the refund policy?" --calls 3
```

`--calls 3` sends the same request three times, appending three metric lines.

Expected output:

```
logged 3 call(s) to llm_metrics.jsonl
```

Look at one line to see what was captured. `tail -1` prints the last line of the file.

```bash
tail -1 llm_metrics.jsonl
```

Expected output (yours will differ):

```
{"ts": "2026-07-25T23:26:25.302908+00:00", "latency_ms": 0.0, "input_tokens": 6, "output_tokens": 16, "cost_usd": 0.000258, "error": false}
```

---

## Exercise 5: Wire a Prometheus and Grafana dashboard

This is the second plan deliverable. Prometheus scrapes a `/metrics` endpoint; Grafana graphs it. We build the exporter that turns your `llm_metrics.jsonl` into the Prometheus text format.

Open the file:

```bash
vi prom_exporter.py
```

Press `i`, then type this in:

```python
"""Expose LLMOps metrics in Prometheus text format over HTTP.

Prometheus scrapes a /metrics endpoint that returns plain text: one line per
metric. Grafana then graphs those metrics. This tiny exporter reads
llm_metrics.jsonl and serves the aggregate numbers a dashboard needs: total
requests, total tokens, total cost, and average latency. No prometheus_client
dependency - we emit the text format by hand so it runs anywhere.
"""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

LOG = "llm_metrics.jsonl"


def aggregate() -> dict:
    path = Path(LOG)
    agg = {"requests": 0, "input_tokens": 0, "output_tokens": 0,
           "cost_usd": 0.0, "latency_sum": 0.0, "errors": 0}
    if not path.exists():
        return agg
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        rec = json.loads(line)
        agg["requests"] += 1
        agg["input_tokens"] += rec.get("input_tokens", 0)
        agg["output_tokens"] += rec.get("output_tokens", 0)
        agg["cost_usd"] += rec.get("cost_usd", 0.0)
        agg["latency_sum"] += rec.get("latency_ms", 0.0)
        if rec.get("error"):
            agg["errors"] += 1
    return agg


def render(agg: dict) -> str:
    avg_latency = (agg["latency_sum"] / agg["requests"]) if agg["requests"] else 0.0
    lines = [
        "# HELP llm_requests_total Total LLM requests served",
        "# TYPE llm_requests_total counter",
        f"llm_requests_total {agg['requests']}",
        "# HELP llm_input_tokens_total Total input tokens",
        "# TYPE llm_input_tokens_total counter",
        f"llm_input_tokens_total {agg['input_tokens']}",
        "# HELP llm_output_tokens_total Total output tokens",
        "# TYPE llm_output_tokens_total counter",
        f"llm_output_tokens_total {agg['output_tokens']}",
        "# HELP llm_cost_usd_total Total model cost in USD",
        "# TYPE llm_cost_usd_total counter",
        f"llm_cost_usd_total {round(agg['cost_usd'], 6)}",
        "# HELP llm_errors_total Total failed calls",
        "# TYPE llm_errors_total counter",
        f"llm_errors_total {agg['errors']}",
        "# HELP llm_avg_latency_ms Average latency in ms",
        "# TYPE llm_avg_latency_ms gauge",
        f"llm_avg_latency_ms {round(avg_latency, 2)}",
    ]
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        body = render(aggregate()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # keep the console quiet


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 9108), Handler)
    print("exporter on http://127.0.0.1:9108/metrics")
    server.serve_forever()
```

Press `Esc`, type `:wq`, press Enter.

Start the exporter in the background. The `&` returns your prompt while it runs.

```bash
python prom_exporter.py &
```

Wait a second, then scrape it the way Prometheus would:

```bash
curl -s http://127.0.0.1:9108/metrics
```

Expected output (yours will differ):

```
# HELP llm_requests_total Total LLM requests served
# TYPE llm_requests_total counter
llm_requests_total 3
# HELP llm_input_tokens_total Total input tokens
# TYPE llm_input_tokens_total counter
llm_input_tokens_total 18
# HELP llm_output_tokens_total Total output tokens
# TYPE llm_output_tokens_total counter
llm_output_tokens_total 48
# HELP llm_cost_usd_total Total model cost in USD
# TYPE llm_cost_usd_total counter
llm_cost_usd_total 0.000774
# HELP llm_errors_total Total failed calls
# TYPE llm_errors_total counter
llm_errors_total 0
# HELP llm_avg_latency_ms Average latency in ms
# TYPE llm_avg_latency_ms gauge
llm_avg_latency_ms 0.0
```

Stop the exporter:

```bash
kill %1
```

`kill %1` stops the background job. In a real deployment you point a Prometheus server at `http://<host>:9108/metrics` with a scrape interval, then add a Grafana panel per metric: request rate, cost over time, token totals, latency, and error rate. The panels are wired to exactly these metric names.

---

## Exercise 6: Score groundedness for the dashboard

The plan wants groundedness on the dashboard alongside tokens, cost, and latency. Groundedness (Concepts 10.3) checks whether an answer is supported by its source. We build an offline proxy scorer.

Open the file:

```bash
vi groundedness.py
```

Press `i`, then type this in:

```python
"""Score groundedness of LLM answers against their source context, offline.

Groundedness (Concepts 10.3) = is every claim in the answer supported by the
retrieved source? A full system uses a scoring model; here we use a simple,
explainable proxy so it runs offline: what fraction of the answer's content
words appear in the provided context. Low overlap flags a possible
hallucination for human review.

Reads a JSONL file of {"answer": ..., "context": ...} records.
Usage: python groundedness.py <records.jsonl>
"""
import json
import re
import sys

STOP = set("the a an of to in for and or is are was were be been being with on "
           "at by from as it this that these those your you we our".split())


def content_words(text: str) -> set:
    words = re.findall(r"[a-z0-9]+", text.lower())
    return {w for w in words if w not in STOP and len(w) > 2}


def score(answer: str, context: str) -> float:
    a = content_words(answer)
    c = content_words(context)
    if not a:
        return 1.0
    return round(len(a & c) / len(a), 3)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: groundedness.py <records.jsonl>")
        return 2
    threshold = 0.5
    total = 0
    grounded = 0
    print(f"{'score':>6}  status  answer")
    for line in open(sys.argv[1]):
        if not line.strip():
            continue
        rec = json.loads(line)
        s = score(rec["answer"], rec["context"])
        ok = s >= threshold
        grounded += int(ok)
        total += 1
        status = "ok    " if ok else "REVIEW"
        print(f"{s:>6.3f}  {status}  {rec['answer'][:50]}")
    rate = round(grounded / total, 3) if total else 0.0
    print("")
    print(f"groundedness_rate: {rate} ({grounded}/{total} above {threshold})")
    return 0 if rate >= 0.7 else 1


if __name__ == "__main__":
    raise SystemExit(main())
```

Press `Esc`, type `:wq`, press Enter.

Create a small test file with two grounded answers and one fabricated one. Open it:

```bash
vi gtest.jsonl
```

Press `i`, then type this in (each record on one line):

```
{"answer": "Refunds are available within 30 days with a receipt.", "context": "Company policy: refunds within 30 days of purchase require the original receipt."}
{"answer": "The warranty lasts 10 years and covers water damage.", "context": "Company policy: refunds within 30 days of purchase require the original receipt."}
{"answer": "To reset your password click Forgot password on the login page.", "context": "Password reset: use the Forgot password link on the login page to reset."}
```

Press `Esc`, type `:wq`, press Enter.

Run the scorer:

```bash
python groundedness.py gtest.jsonl
```

Expected output (yours will differ):

```
 score  status  answer
 0.800  ok      Refunds are available within 30 days with a receip
 0.000  REVIEW  The warranty lasts 10 years and covers water damag
 0.833  ok      To reset your password click Forgot password on th

groundedness_rate: 0.667 (2/3 above 0.5)
```

The fabricated warranty answer scored 0.0 and was flagged REVIEW - none of its content words appear in the source. That is a hallucination the dashboard would surface. In production you push `groundedness_rate` into Prometheus as another gauge next to cost and latency.

---

## What you produced

- A prompt regression test wired into a CI workflow that blocks a bad prompt (plan deliverable 1).
- A Prometheus exporter and the panel plan for tokens, cost, latency, and groundedness in Grafana (plan deliverable 2).
- An offline LLM client, a cost logger, and a groundedness scorer you reuse in the SURVIVE scenarios.

Keep every file. The SURVIVE scenarios in this tier build directly on the prompt regression test, the cost logger, and the registry from BUILD.

Prof. Happy (SUTA Labs)
