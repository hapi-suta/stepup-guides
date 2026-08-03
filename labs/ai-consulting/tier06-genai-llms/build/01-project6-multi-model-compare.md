# BUILD: Project 6 - Multi-Model Comparison Harness

**Tier 6 - the generative-AI capstone.** You will build one application that sends the SAME structured task to multiple LLMs and compares them side by side: accuracy, cost, speed, output consistency, refusal behavior, and structured-output quality. This is exactly the artifact a consultant builds when a client asks "which model should we use?" - you answer with evidence, not opinion.

**Validated on:** CentOS Stream 9, Python 3.12. All output shown is real (truncated where long; timings and token counts will differ on your machine).

**Prerequisite:** you read Concepts 6.1-6.4. You do not need any prior LLM code.

**API keys - read this first.** Real LLM calls need an API key that YOU supply through an environment variable (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`). This project is written so it **runs and is fully demonstrable with NO key at all**, using a built-in MOCK provider (a local stub). The mock is deterministic and free. When (and only when) you want to compare against a real model, you set the matching key and the app picks it up automatically. Every step below tells you clearly whether it needs a real key.

**What you build:** a folder `project6-compare/` with a small provider layer (mock + optional real Claude), a comparison runner, and a printed report table. You will run the whole thing on the mock first, see a real comparison table, then optionally add a real provider.

---

## Step 1: Create the project folder

On your **lab server**, as **ec2-user**, make a working folder:

```bash
mkdir -p ~/project6-compare
```

`mkdir -p` creates the folder (`-p` means "do not error if it already exists"). Move into it:

```bash
cd ~/project6-compare
```

`cd` changes into the folder so every file we create lands here.

---

## Step 2: Create and activate a virtual environment

A virtual environment keeps this project's packages separate from the system Python.

Still on your **lab server**, as **ec2-user**, in `~/project6-compare`:

```bash
python3.12 -m venv .venv
```

`-m venv` runs Python's built-in venv module; `.venv` is the folder it creates. Activate it:

```bash
source .venv/bin/activate
```

`source` runs the activate script in your current shell. Your prompt now shows `(.venv)` at the front, which means the environment is on.

---

## Step 3: Install the one library we need

We only need one HTTP-friendly SDK to make an *optional* real call later. The mock provider needs nothing but the standard library.

Still in the activated environment:

```bash
pip install anthropic
```

`pip install` downloads and installs the package. `anthropic` is the official SDK for calling Claude; we import it lazily so the app still runs without it if you only ever use the mock. Confirm it landed:

```bash
pip show anthropic | head -2
```

`pip show` prints package metadata; `head -2` keeps it to the first two lines.

Expected output (yours will differ):

```
Name: anthropic
Version: 0.69.0
```

---

## Step 4: Define the shared task

The whole point is to send *the same* task to every model. We make it a structured extraction task with a known correct answer, so we can score accuracy objectively.

Still on your **lab server**, as **ec2-user**, in `~/project6-compare`, open a new file with vi:

```bash
vi task.py
```

Press `i` to enter insert mode, then type (or paste) the following:

```python
"""The shared task every model gets, plus the known-correct answer.

The task: read a short support ticket and return structured JSON with the
category, urgency, and whether a refund is requested. Because we know the
right answer, we can score each model's accuracy objectively.
"""

# The system prompt sets standing behavior (Concepts 6.2).
SYSTEM_PROMPT = (
    "You are a support-ticket triage assistant. "
    "Respond with ONLY a JSON object, no prose before or after, of the form: "
    '{"category": "billing|technical|account|other", '
    '"urgency": "low|medium|high", '
    '"refund_requested": true|false}. '
    "If unsure about category, use \"other\"."
)

# The user message is the ticket to classify.
TICKET = (
    "I was charged twice for my subscription this month and I need the "
    "duplicate charge refunded today before it overdraws my account. "
    "This is urgent."
)

# The answer a correct model should produce (our grading key).
EXPECTED = {
    "category": "billing",
    "urgency": "high",
    "refund_requested": True,
}
```

Press `Esc` to leave insert mode, then type `:wq` and press Enter to save and quit vi.

---

## Step 5: Write the provider layer (the anti-lock-in abstraction)

This is the heart of the design from Concepts 6.3: a thin interface so every provider looks the same to the rest of the app, and a MOCK provider so the app runs with no key. Each provider returns the same result shape: the raw text, the token counts, the elapsed time, and whether it refused.

Still on your **lab server**, as **ec2-user**, in `~/project6-compare`, open a new file:

```bash
vi providers.py
```

Press `i`, then enter the following. Read the comments as you go.

```python
"""Provider layer: every model looks the same to the rest of the app.

Each provider exposes .name and .complete(system, user, max_tokens) and returns
a ProviderResult. The MockProvider needs no key and runs offline, so the whole
harness is demonstrable for free. The ClaudeProvider is used ONLY if a real
ANTHROPIC_API_KEY is present.
"""

import os
import time
from dataclasses import dataclass


@dataclass
class ProviderResult:
    provider: str          # which provider produced this
    text: str              # the raw response text
    input_tokens: int      # tokens sent (estimate for the mock)
    output_tokens: int     # tokens received
    seconds: float         # wall-clock time for the call
    refused: bool          # did the model decline?
    error: str = ""        # non-empty if the call failed


def _approx_tokens(text: str) -> int:
    """Rough token estimate: ~4 characters per token (Concepts 6.1).

    The mock uses this so we do not need a real tokenizer. For REAL providers
    you should count tokens with the model's own tokenizer instead (Step 9).
    """
    return max(1, len(text) // 4)


class MockProvider:
    """A local stub that imitates a model. No key, no network, deterministic.

    It "reads" the ticket and returns plausible structured JSON, so you can
    exercise the whole harness for free. It deliberately introduces a small
    imperfection (lowercased-then-fine) so the comparison has something to show.
    """

    name = "mock"

    def complete(self, system: str, user: str, max_tokens: int) -> ProviderResult:
        start = time.perf_counter()
        # Pretend to think. Keep it tiny so the lab is fast.
        time.sleep(0.05)

        text = user.lower()
        # Very simple keyword logic - this is a STUB, not a real model.
        category = "billing" if ("charge" in text or "refund" in text) else "other"
        urgency = "high" if ("urgent" in text or "today" in text) else "medium"
        refund = "refund" in text
        body = (
            '{"category": "%s", "urgency": "%s", "refund_requested": %s}'
            % (category, urgency, "true" if refund else "false")
        )
        elapsed = time.perf_counter() - start
        return ProviderResult(
            provider=self.name,
            text=body,
            input_tokens=_approx_tokens(system + user),
            output_tokens=_approx_tokens(body),
            seconds=elapsed,
            refused=False,
        )


class ClaudeProvider:
    """Real Claude. Used only if ANTHROPIC_API_KEY is set. Requires a REAL KEY."""

    name = "claude"

    def __init__(self):
        # Import lazily so the app runs without the SDK when using the mock.
        import anthropic

        self._client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from env
        # Always use the exact current model ID from Anthropic's docs.
        self._model = os.environ.get("CLAUDE_MODEL", "claude-opus-4-8")

    def complete(self, system: str, user: str, max_tokens: int) -> ProviderResult:
        start = time.perf_counter()
        try:
            resp = self._client.messages.create(
                model=self._model,
                max_tokens=max_tokens,
                system=system,
                messages=[{"role": "user", "content": user}],
            )
        except Exception as exc:  # surface, never swallow (Concepts 6.4)
            elapsed = time.perf_counter() - start
            return ProviderResult(
                provider=self.name, text="", input_tokens=0, output_tokens=0,
                seconds=elapsed, refused=False, error=str(exc),
            )
        elapsed = time.perf_counter() - start
        refused = resp.stop_reason == "refusal"
        text = ""
        for block in resp.content:
            if block.type == "text":
                text += block.text
        return ProviderResult(
            provider=self.name,
            text=text,
            input_tokens=resp.usage.input_tokens,
            output_tokens=resp.usage.output_tokens,
            seconds=elapsed,
            refused=refused,
        )


def available_providers():
    """Return the providers we can actually use right now.

    The mock is ALWAYS available. Claude is added only if a real key is present,
    with a clear message either way so you know why.
    """
    providers = [MockProvider()]
    if os.environ.get("ANTHROPIC_API_KEY"):
        try:
            providers.append(ClaudeProvider())
            print("[info] ANTHROPIC_API_KEY found - real Claude included.")
        except Exception as exc:
            print(f"[warn] Claude key present but SDK not ready: {exc}")
    else:
        print("[info] No ANTHROPIC_API_KEY set - running MOCK only. "
              "Set your API key to compare a real model:")
        print("       export ANTHROPIC_API_KEY=sk-ant-...")
    return providers
```

Press `Esc`, then type `:wq` and press Enter to save and quit.

---

## Step 6: Write the comparison runner and report

This runs the shared task through every available provider, scores each result, and prints a comparison table across all six dimensions.

Still on your **lab server**, as **ec2-user**, in `~/project6-compare`, open a new file:

```bash
vi compare.py
```

Press `i`, then enter the following.

```python
"""Send the shared task to every provider and print a comparison table."""

import json

from task import SYSTEM_PROMPT, TICKET, EXPECTED, {}
from providers import available_providers

# Rough per-1K-token prices in US dollars, for cost ESTIMATION only.
# These are illustrative - always confirm real current prices from the provider
# (Concepts 6.3/6.4) before quoting a client.
PRICE_PER_1K = {
    "mock": {"input": 0.0, "output": 0.0},
    "claude": {"input": 0.005, "output": 0.025},
}


def parse_json(text: str):
    """Try to parse the model's output as JSON. Return None on failure.

    Real models sometimes wrap JSON in prose; a robust harness must not crash
    when that happens (Concepts 6.4). We just record it as a structure failure.
    """
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return None


def score_accuracy(parsed) -> str:
    """Compare the parsed answer field-by-field against EXPECTED."""
    if parsed is None:
        return "n/a (bad JSON)"
    correct = sum(1 for k, v in EXPECTED.items() if parsed.get(k) == v)
    return f"{correct}/{len(EXPECTED)}"


def estimate_cost(name, r) -> float:
    price = PRICE_PER_1K.get(name, {"input": 0.0, "output": 0.0})
    return (r.input_tokens / 1000.0) * price["input"] + \
           (r.output_tokens / 1000.0) * price["output"]


def main():
    providers = available_providers()
    print(f"\nSending the SAME task to {len(providers)} provider(s).\n")

    rows = []
    for p in providers:
        r = p.complete(SYSTEM_PROMPT, TICKET, max_tokens=200)
        if r.error:
            print(f"[error] {p.name}: {r.error}")
        parsed = parse_json(r.text)
        rows.append({
            "provider": r.provider,
            "accuracy": score_accuracy(parsed),
            "valid_json": "yes" if parsed is not None else "no",
            "refused": "yes" if r.refused else "no",
            "seconds": f"{r.seconds:.3f}",
            "in_tok": r.input_tokens,
            "out_tok": r.output_tokens,
            "cost_usd": f"{estimate_cost(r.provider, r):.6f}",
            "raw": r.text[:60],
        })

    # Print the comparison table.
    header = ["provider", "accuracy", "valid_json", "refused",
              "seconds", "in_tok", "out_tok", "cost_usd"]
    widths = {h: max(len(h), *(len(str(row[h])) for row in rows)) for h in header}
    line = "  ".join(h.ljust(widths[h]) for h in header)
    print(line)
    print("-" * len(line))
    for row in rows:
        print("  ".join(str(row[h]).ljust(widths[h]) for h in header))

    print("\nRaw output (first 60 chars each):")
    for row in rows:
        print(f"  {row['provider']}: {row['raw']}")

    # Output-consistency note: do all providers agree?
    answers = {row["provider"]: row["raw"] for row in rows}
    distinct = len(set(answers.values()))
    print(f"\nOutput consistency: {distinct} distinct answer(s) across "
          f"{len(rows)} provider(s).")


if __name__ == "__main__":
    main()
```

Press `Esc`, then type `:wq` and press Enter to save and quit.

Note the `{}` on the import line above is a typo we will fix in the next step on purpose - it lets you practice reading a Python error. If you already spotted it, good instinct; leave it for now so the next step teaches error reading.

---

## Step 7: Run it (and read your first error)

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python compare.py
```

Because of the deliberate `{}` on the import line, Python raises a syntax error.

Expected output (yours will differ):

```
  File "/home/ec2-user/project6-compare/compare.py", line 5
    from task import SYSTEM_PROMPT, TICKET, EXPECTED, {}
                                                      ^
SyntaxError: invalid syntax
```

Reading a traceback is a core skill. It tells you the file, the line, and the problem. Fix it: open the file again:

```bash
vi compare.py
```

Move to the import line (press `/` then type `EXPECTED` and press Enter to jump to it). Press `i`, delete the `, {}` so the line reads exactly:

```python
from task import SYSTEM_PROMPT, TICKET, EXPECTED
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 8: Run the real comparison (mock only, no key needed)

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python compare.py
```

This time it runs cleanly on the mock provider - no API key required.

Expected output (yours will differ):

```
[info] No ANTHROPIC_API_KEY set - running MOCK only. Set your API key to compare a real model:
       export ANTHROPIC_API_KEY=sk-ant-...

Sending the SAME task to 1 provider(s).

provider  accuracy  valid_json  refused  seconds  in_tok  out_tok  cost_usd
---------------------------------------------------------------------------
mock      3/3       yes         no       0.054    102     17       0.000000

Raw output (first 60 chars each):
  mock: {"category": "billing", "urgency": "high", "refund_requested

Output consistency: 1 distinct answer(s) across 1 provider(s).
```

Read what the table tells you. The mock scored 3/3 on accuracy, returned valid JSON, did not refuse, took ~54ms, used 102 input and 17 output tokens, and cost nothing. This is the shape of the deliverable - one glance answers "how good, how fast, how much, how reliable".

---

## Step 9: Add a real tokenizer count (needs a real key - optional)

The mock estimates tokens as chars/4. For a real provider you should count tokens with the model's own tokenizer (Concepts 6.4). This step is **optional and requires a real `ANTHROPIC_API_KEY`.** If you do not have one, skip to Step 10 - the harness is already complete and demonstrable on the mock.

If you do have a key, first set it:

```bash
export ANTHROPIC_API_KEY=sk-ant-your-real-key-here
```

`export` puts the key in your shell environment so the SDK finds it. Now open `providers.py` again to use the real token counter in `ClaudeProvider`:

```bash
vi providers.py
```

Press `/` then type `resp = self._client.messages.create` and press Enter to find the call. We will add an accurate input-token count just before it. Press `i` and, on the line immediately above `resp = self._client.messages.create(`, add:

```python
            # Accurate input-token count from the model's own tokenizer.
            counted = self._client.messages.count_tokens(
                model=self._model,
                system=system,
                messages=[{"role": "user", "content": user}],
            )
```

Then change the returned `input_tokens=resp.usage.input_tokens,` line for the SUCCESS path to prefer the counted value if usage is unavailable - but since real responses already carry `resp.usage.input_tokens`, the extra `count_tokens` call is mainly to show cost *before* sending in your own tools. For now, just confirm it runs. Press `Esc`, type `:wq`, press Enter.

---

## Step 10: Run the full comparison (needs a real key - optional)

**This step requires a real `ANTHROPIC_API_KEY`** (set in Step 9). If you do not have one, skip it; your project is complete on the mock.

With the key set, run again:

```bash
python compare.py
```

Now both providers run and you get a true head-to-head.

Expected output (yours will differ - real timings, tokens, and cost depend on the live model):

```
[info] ANTHROPIC_API_KEY found - real Claude included.

Sending the SAME task to 2 provider(s).

provider  accuracy  valid_json  refused  seconds  in_tok  out_tok  cost_usd
---------------------------------------------------------------------------
mock      3/3       yes         no       0.054    102     17       0.000000
claude    3/3       yes         no       1.284    92      21       0.000985

Raw output (first 60 chars each):
  mock:   {"category": "billing", "urgency": "high", "refund_requested
  claude: {"category": "billing", "urgency": "high", "refund_requested

Output consistency: 1 distinct answer(s) across 2 provider(s).
```

Now the table earns its keep: the real model matched the mock on accuracy and JSON validity, but was ~25x slower and cost real money. That is exactly the kind of trade-off a client is paying you to surface.

---

## Step 11: Test the refusal and bad-JSON paths (no key needed)

A comparison harness must also show *misbehavior*. Let's prove the harness handles a model that returns unparseable output, using a second mock. Open `providers.py`:

```bash
vi providers.py
```

Press `G` to jump to the end of the file. Press `o` to open a new line below, then type a second mock that returns broken JSON and a refusal flag:

```python

class ChattyMockProvider:
    """A stub that wraps its JSON in prose - a common real-world failure that
    breaks naive parsers. Lets us prove the harness records it as invalid JSON
    instead of crashing. No key, no network."""

    name = "chatty-mock"

    def complete(self, system: str, user: str, max_tokens: int) -> ProviderResult:
        import time
        start = time.perf_counter()
        time.sleep(0.02)
        body = ('Sure! Here is the triage result you asked for:\n'
                '{"category": "billing", "urgency": "high", '
                '"refund_requested": true}')
        return ProviderResult(
            provider=self.name, text=body,
            input_tokens=_approx_tokens(system + user),
            output_tokens=_approx_tokens(body),
            seconds=time.perf_counter() - start, refused=False,
        )
```

Now find `available_providers` (press `/` then type `def available_providers` and Enter). We will add the chatty mock to the list. Press `/` then type `providers = [MockProvider()]` and Enter to land on it, press `i`, and change that line to:

```python
    providers = [MockProvider(), ChattyMockProvider()]
```

Press `Esc`, type `:wq`, press Enter. Run it (unset the real key first so this is free and deterministic):

```bash
unset ANTHROPIC_API_KEY
```

```bash
python compare.py
```

Expected output (yours will differ):

```
[info] No ANTHROPIC_API_KEY set - running MOCK only. Set your API key to compare a real model:
       export ANTHROPIC_API_KEY=sk-ant-...

Sending the SAME task to 2 provider(s).

provider     accuracy        valid_json  refused  seconds  in_tok  out_tok  cost_usd
------------------------------------------------------------------------------------
mock         3/3             yes         no       0.050    102     17       0.000000
chatty-mock  n/a (bad JSON)  no          no       0.020    102     28       0.000000

Raw output (first 60 chars each):
  mock: {"category": "billing", "urgency": "high", "refund_requested
  chatty-mock: Sure! Here is the triage result you asked for:
{"category":

Output consistency: 2 distinct answer(s) across 2 provider(s).
```

The harness correctly flags `chatty-mock` as producing invalid JSON (n/a accuracy, valid_json = no) instead of crashing. That "structured-output quality" column is often the deciding factor when a client's pipeline depends on parseable output.

---

## Step 12: Review what you built

You now have a working multi-model comparison harness that:

- Sends **one shared, structured task** to every provider.
- Scores **accuracy** against a known answer.
- Reports **cost** (from token counts x price), **speed** (wall-clock), **output consistency** (distinct answers), **refusal behavior**, and **structured-output quality** (valid JSON or not).
- Runs **fully on a free, keyless mock** and optionally against a **real model** when a key is supplied.
- Uses a **clean provider abstraction** (Concepts 6.3) so adding OpenAI, Gemini, or a local model is one new class.

List your files to confirm:

```bash
ls -1
```

Expected output (yours will differ):

```
compare.py
providers.py
task.py
```

**What needed a real key vs the mock:**

- Steps 1-8, 11-12: **mock only, no key** - the full harness is demonstrable for free.
- Steps 9-10: **real `ANTHROPIC_API_KEY` required** - only to compare an actual model and use its real tokenizer.

That separation is the whole design philosophy of this tier: the logic is provable for free, and a real key only buys you a real comparison. Take this harness into USE, where you turn its output into a client-facing selection matrix.

Prof. Happy (SUTA Labs)
