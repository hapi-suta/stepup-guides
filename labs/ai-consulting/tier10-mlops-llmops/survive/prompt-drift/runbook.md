# SURVIVE: Prompt drift - the regression suite catches it

Someone "improved" the app's prompt. Quality quietly collapsed. No code errored,
no alarm sounded - the answers just stopped containing the facts users need.
This is prompt drift (Concepts 10.5): quality drops because the prompt changed,
not the data. The only thing standing between you and an angry customer is the
prompt regression suite (Concepts 10.4), and in this scenario you use it to
catch the drift before it ships.

Your job is to run the regression suite, watch it fail, find the bad prompt,
restore a good one so the golden set passes, and document the finding. This runs
entirely offline against a mock LLM - no key needed.

Before you start, run the injector if you have not already:

```
bash inject.sh
```

That builds `~/survive-prompt-drift`, installs a golden set and a regression
test, injects a drifted prompt template, and runs the suite so you can see it
fail.

---

## Layer 1: Detect

On your lab server, as ec2-user, move into the working directory. `cd` changes
your current directory so the commands find the files.

```
cd ~/survive-prompt-drift
```

Activate the virtual environment. `source` loads the venv so `python` uses the
right interpreter.

```
source .venv/bin/activate
```

Run the prompt regression suite. It sends each golden question through the
current prompt template and checks the answer contains the required facts.

```
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

Every case fails and the answers are truncated to one word ("The", "Refunds",
"To"). The suite is doing exactly its job: catching a quality regression before
it reaches users. Now find out why.

---

## Layer 2: Diagnose

The answers are one word each. Something is telling the model to be terse. The
prompt template is the first suspect. Look at it. `cat` prints the file.

```
cat prompt_template.txt
```

Expected output (yours will differ):

```
Answer in one word only. {question}
```

There it is. The prompt template was edited to force one-word answers. That edit
fixed nobody's problem and broke every golden case - the classic prompt-drift
pattern: a well-meaning tweak that silently degrades quality. The data never
changed; the prompt did. Confirm that the underlying model still knows the
answers by asking it directly without the bad template. `python -c` runs a
one-line program.

```
python -c "from llm_client import complete; print(complete('What is the refund policy?'))"
```

Expected output (yours will differ):

```
Refunds are available within 30 days of purchase with a receipt.
```

The model is fine. The prompt is the problem. This confirms prompt drift, not
data drift or a model change.

---

## Layer 3: Correct and validate

Restore a good prompt. The simplest correct fix here is to remove the drifted
template so the app falls back to the default (pass the question straight
through). `rm -f` deletes the file without complaining if it is missing.

```
rm -f prompt_template.txt
```

Re-run the regression suite to prove the golden set is green again.

```
python prompt_regression.py
```

Expected output (yours will differ):

```
PASS: 'What is the capital of France?'
PASS: 'What is the refund policy?'
PASS: 'How do I reset my password?'

RESULT: PASS - all 3 golden cases passed
```

The golden set passes. Quality is restored. Now document the finding. Open the
file with vi.

```
vi prompt_drift_findings.md
```

In vi, press `i` to enter insert mode, type your findings, then press `Esc` and
type `:wq` and press Enter to save and quit. Make sure you mention prompt drift,
the golden set / regression test, and a prevention (versioning, restore, or a CI
gate). Something like:

```markdown
# Prompt drift findings

## Detection
The prompt regression suite failed all 3 golden cases after a prompt edit. The
answers were truncated ("The", "Refunds") and no longer contained the required
facts.

## Cause
Prompt drift: prompt_template.txt was edited to force "one word only" answers.
The data did not change - the prompt did.

## Fix
Restored the default prompt template so the model returns full answers. The
golden set is green again.

## Prevention
Version prompt templates in git and run prompt_regression.py as a CI gate so a
prompt change that fails the golden set cannot ship. Log the prompt version with
each response so a future regression is traceable to the exact edit.
```

Now validate your work. This runs the checker, which confirms the drift is
removed, the golden set passes, and your findings cover the right points.

```
bash validate.sh
```

Expected output (yours will differ):

```
=== Validating SURVIVE: prompt-drift ===
OK:   prompt template no longer forces a terse answer
OK:   prompt regression suite passes (golden set is green)
OK:   prompt_drift_findings.md exists
OK:   findings mention prompt drift
OK:   findings mention the golden set / regression test
OK:   findings name a prevention (versioning/restore/CI gate)
RESULT: PASS - prompt drift detected, corrected, golden set green, documented
```

If you see RESULT: PASS you have survived the scenario.

Note: the validator accepts either removing the drifted template or replacing it
with a good one that does not force a terse answer - both are correct fixes.

---

## The lesson

A prompt is code. It changes behaviour, so it must be versioned and tested like
code. The reason this drift was catchable in seconds rather than discovered by a
customer is the golden set plus the regression test wired into CI (USE Exercise
3). Without that gate, the one-word template would have shipped and every user
would have gotten useless answers until someone complained. The consulting
takeaway: for any LLM app, prompt versioning plus a golden-set regression gate
is not optional - it is the seatbelt.

Prof. Happy (SUTA Labs)
