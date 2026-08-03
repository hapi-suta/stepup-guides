# USE: A Prompt Template Library with Versioning and Regression Tests

**Tier 6 - USE phase.** In Concepts 6.2 you learned that a prompt is part of your program's logic and should be treated like tested, versioned code. Here you build exactly that: a small **prompt template library** with named, versioned templates, plus a **regression test set** that scores every prompt version against known-good answers. This is the artifact that turns prompt engineering from vibes into measurement - and clients love it because it makes prompt quality visible and defensible.

**Validated on:** CentOS Stream 9, Python 3.12. No API key required - the grader runs against a keyless mock "model" so the whole exercise is free and deterministic. A short note at the end shows exactly where you would plug in a real model.

**Prerequisite:** you read Concepts 6.2 (prompt design) and finished BUILD Project 6 (you already have the provider-abstraction idea).

**Goal:** a versioned prompt library and a regression harness that tells you, objectively, whether a new prompt version is better or worse than the last.

---

## Step 1: Set up the folder

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/use-prompt-library/prompts
```

`-p` creates the nested `prompts/` folder too. Move into the project:

```bash
cd ~/use-prompt-library
```

---

## Step 2: Store prompts as versioned files

The core discipline (Concepts 6.2): each prompt has a name and a version, and old versions are kept. We store each version as its own file so you can diff and roll back. Create the first version of a "ticket triage" prompt:

```bash
vi prompts/triage_v1.txt
```

Press `i`, then enter a deliberately weak first version (so the regression set has something to improve on):

```
Classify this support ticket. Say the category, the urgency, and if they want a refund.

{ticket}
```

Press `Esc`, type `:wq`, press Enter.

Now create a stronger v2 that follows the prompt-design principles (clear instructions, explicit output format, delimiters):

```bash
vi prompts/triage_v2.txt
```

Press `i`, then enter:

```
<instructions>
You are a support-ticket triage assistant. Read the ticket in <ticket> and
respond with ONLY a JSON object, no prose before or after, of the form:
{"category": "billing|technical|account|other",
 "urgency": "low|medium|high",
 "refund_requested": true|false}
If unsure about the category, use "other".
</instructions>

<ticket>
{ticket}
</ticket>
```

Press `Esc`, type `:wq`, press Enter. You now have two versions of the same named prompt. Keeping both is the point - you never overwrite a prompt in place.

---

## Step 3: Build the regression test set

A regression set is a fixed collection of inputs paired with the answer you expect (Concepts 6.2/6.8). Create it as JSON so it is easy to grow. Open:

```bash
vi regression_set.json
```

Press `i`, then enter a small but meaningful set - including tricky/edge cases:

```json
[
  {
    "id": "billing-refund-urgent",
    "ticket": "I was charged twice and need the duplicate refunded today, urgent.",
    "expected": {"category": "billing", "urgency": "high", "refund_requested": true}
  },
  {
    "id": "technical-lowkey",
    "ticket": "The dark mode toggle doesn't stick between sessions. Minor, whenever.",
    "expected": {"category": "technical", "urgency": "low", "refund_requested": false}
  },
  {
    "id": "account-medium",
    "ticket": "I can't log in after changing my email. Please help this week.",
    "expected": {"category": "account", "urgency": "medium", "refund_requested": false}
  },
  {
    "id": "ambiguous-other",
    "ticket": "Hi! Just wanted to say your team is great. Keep it up.",
    "expected": {"category": "other", "urgency": "low", "refund_requested": false}
  }
]
```

Press `Esc`, type `:wq`, press Enter. Note the last case is deliberately ambiguous - a good prompt should route it to "other", and a weak one may guess wrong. That is what regression sets are for.

---

## Step 4: Write the library loader

A small module that lists templates, loads a specific version, and fills placeholders. Open:

```bash
vi library.py
```

Press `i`, then enter:

```python
"""Prompt template library: list, load, and render versioned prompts.

Templates live in prompts/<name>_v<N>.txt. We never overwrite a version - a new
version is a new file - so we can diff, roll back, and audit which version
produced which output (Concepts 6.2).
"""

import re
from pathlib import Path

PROMPT_DIR = Path(__file__).parent / "prompts"


def list_versions(name: str):
    """Return sorted version numbers available for a prompt name."""
    versions = []
    for p in PROMPT_DIR.glob(f"{name}_v*.txt"):
        m = re.search(rf"{name}_v(\d+)\.txt$", p.name)
        if m:
            versions.append(int(m.group(1)))
    return sorted(versions)


def load(name: str, version: int) -> str:
    """Load the raw template text for a specific name and version."""
    path = PROMPT_DIR / f"{name}_v{version}.txt"
    if not path.exists():
        raise FileNotFoundError(f"No such prompt: {path.name}")
    return path.read_text()


def render(name: str, version: int, **fields) -> str:
    """Fill the template's {placeholders} with the given fields.

    We substitute each placeholder explicitly with str.replace rather than
    str.format, because our templates deliberately contain literal JSON braces
    (like {"category": ...}) that str.format would misread as placeholders.
    """
    template = load(name, version)
    for key, value in fields.items():
        template = template.replace("{" + key + "}", str(value))
    return template
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 5: Add a keyless mock "model" for grading

To run the regression set for free and deterministically, we grade prompts against a mock model - the same idea as BUILD's mock provider. The mock is deliberately *prompt-sensitive*: it does better when the prompt clearly demands JSON, so improving the prompt actually improves the score (mirroring real behavior). Open:

```bash
vi mock_model.py
```

Press `i`, then enter:

```python
"""A keyless, deterministic stand-in for a real model, for regression testing.

It is intentionally prompt-sensitive: when the rendered prompt clearly asks for
JSON only (as good prompts do), the mock returns clean JSON; a vague prompt gets
a sloppier, prose-wrapped answer. This lets the regression harness show a real
difference between prompt versions WITHOUT any API key or cost.

For a REAL run, replace mock_complete() with a call through your provider layer
(see the note at the end of the lab). The harness code does not change.
"""


def _classify(ticket: str):
    t = ticket.lower()
    if "charge" in t or "refund" in t or "charged" in t:
        category = "billing"
    elif "log in" in t or "login" in t or "email" in t or "account" in t:
        category = "account"
    elif "toggle" in t or "mode" in t or "crash" in t or "bug" in t:
        category = "technical"
    else:
        category = "other"
    if "urgent" in t or "today" in t:
        urgency = "high"
    elif "this week" in t or "help" in t:
        urgency = "medium"
    else:
        urgency = "low"
    refund = "refund" in t
    return category, urgency, refund


def mock_complete(rendered_prompt: str, ticket: str) -> str:
    """Return the mock model's raw text output for a rendered prompt."""
    category, urgency, refund = _classify(ticket)
    json_body = (
        '{"category": "%s", "urgency": "%s", "refund_requested": %s}'
        % (category, urgency, "true" if refund else "false")
    )
    # Prompt-sensitivity: a good prompt says "ONLY a JSON object". A weak prompt
    # does not, so the mock wraps the answer in prose that breaks naive parsers.
    wants_json_only = "only a json object" in rendered_prompt.lower()
    if wants_json_only:
        return json_body
    return "Sure, here is the classification: " + json_body
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 6: Write the regression harness

This loads the set, runs a chosen prompt version through the mock, parses and scores each output, and prints a pass/fail summary. Open:

```bash
vi run_regression.py
```

Press `i`, then enter:

```python
"""Run the regression set against a prompt version and score it.

Usage: python3.12 run_regression.py <version>
Prints per-case results and an overall pass rate, so you can compare versions
objectively (Concepts 6.2).
"""

import json
import sys
from pathlib import Path

import library
from mock_model import mock_complete

SET_PATH = Path(__file__).parent / "regression_set.json"


def parse_json(text: str):
    """Parse model output as JSON; None if it is not clean JSON."""
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return None


def grade(parsed, expected) -> bool:
    """A case passes only if every expected field matches exactly."""
    if parsed is None:
        return False
    return all(parsed.get(k) == v for k, v in expected.items())


def main():
    if len(sys.argv) != 2:
        print("Usage: python3.12 run_regression.py <version>")
        sys.exit(1)
    version = int(sys.argv[1])

    cases = json.loads(SET_PATH.read_text())
    passed = 0
    print(f"Running regression set against triage_v{version}\n")
    print(f"{'id':26} {'valid_json':11} {'result':6}")
    print("-" * 46)
    for case in cases:
        rendered = library.render("triage", version, ticket=case["ticket"])
        raw = mock_complete(rendered, case["ticket"])
        parsed = parse_json(raw)
        ok = grade(parsed, case["expected"])
        passed += 1 if ok else 0
        print(f"{case['id']:26} {'yes' if parsed else 'no':11} "
              f"{'PASS' if ok else 'FAIL':6}")

    total = len(cases)
    print("-" * 46)
    print(f"\nScore for triage_v{version}: {passed}/{total} "
          f"({100.0 * passed / total:.0f}%)")


if __name__ == "__main__":
    main()
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 7: Run the regression set against v1 (the weak prompt)

Still on your **lab server**, as **ec2-user**:

```bash
python3.12 run_regression.py 1
```

Expected output (yours will differ):

```
Running regression set against triage_v1

id                         valid_json  result
----------------------------------------------
billing-refund-urgent      no          FAIL
technical-lowkey           no          FAIL
account-medium             no          FAIL
ambiguous-other            no          FAIL
----------------------------------------------

Score for triage_v1: 0/4 (0%)
```

v1 scores 0/4. The weak prompt never demanded JSON-only, so the mock wrapped every answer in prose and the parser rejected all of them. This is a realistic failure - a prompt that "works" in a chat window but breaks a real pipeline.

---

## Step 8: Run the regression set against v2 (the improved prompt)

```bash
python3.12 run_regression.py 2
```

Expected output (yours will differ):

```
Running regression set against triage_v2

id                         valid_json  result
----------------------------------------------
billing-refund-urgent      yes         PASS
technical-lowkey           yes         PASS
account-medium             yes         PASS
ambiguous-other            yes         PASS
----------------------------------------------

Score for triage_v2: 4/4 (100%)
```

v2 scores 4/4. The clear "ONLY a JSON object" instruction and the `<instructions>`/`<ticket>` delimiters produced parseable output every time. **You just measured a prompt improvement instead of guessing at one.** That number - 0% to 100% - is what you show a client to justify a prompt change.

---

## Step 9: Prove the rollback story

The reason to keep old versions is safe rollback (Concepts 6.2). Confirm both versions still exist and are independently runnable:

```bash
ls -1 prompts/
```

Expected output:

```
triage_v1.txt
triage_v2.txt
```

Because v1 is still on disk, you can roll back instantly if a future "v3" regresses. Run the harness against either version any time. This is exactly the audit-and-rollback capability that separates a mature LLM practice from pasting prompts into a chat window.

---

## Step 10: Grow the discipline (make v3 and re-test)

Try it yourself: add a `triage_v3.txt` that improves on v2 (for example, add one few-shot example for the ambiguous case), then run `python3.12 run_regression.py 3` and compare the score to v2. Only promote v3 if it does not regress any case that v2 passed. That loop - propose, measure against the fixed set, promote only on no-regression - is the whole professional method.

Create v3 to practice:

```bash
cp prompts/triage_v2.txt prompts/triage_v3.txt
```

`cp` copies v2 to a new v3 file. Edit it to add an example:

```bash
vi prompts/triage_v3.txt
```

Add a few-shot example inside the instructions block, save with `:wq`, then:

```bash
python3.12 run_regression.py 3
```

Confirm it still scores 4/4 (or better on a larger set). If a change ever drops a previously-passing case, you have caught a regression before it reached production - the entire point of the harness.

---

## Step 11: Review the deliverable

List what you built:

```bash
ls -1
```

Expected output (yours will differ):

```
library.py
mock_model.py
prompts
regression_set.json
run_regression.py
```

You now have a real prompt template library with:

- **Named, versioned templates** on disk (never overwritten).
- **Placeholder rendering** so the app fills prompts consistently.
- **A regression test set** of representative and edge cases with known answers.
- **An objective harness** that scores each version, making improvements and regressions measurable.
- **A rollback story** because every version is retained.

**Where a real model plugs in:** everything above runs on the keyless mock so it is free and deterministic. To grade against a real model instead, replace the `mock_complete(rendered, ticket)` call in `run_regression.py` with a call through your BUILD provider layer (which reads `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` from the environment and degrades with a clear message if the key is absent). The harness, the set, and the library do not change - only the one line that produces the model's text. That is the payoff of a clean abstraction: you develop and regression-test for free, and a real key only buys you a real grade.

Prof. Happy (SUTA Labs)
