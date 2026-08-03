# USE: Run a Real AI Impact Assessment on Your Tier 7 Assistant

**Tier 12 - USE phase.** In BUILD you assembled the impact-assessment template. Now
you apply it for real against a system you actually built: the secure bilingual
enterprise knowledge assistant from Tier 7. A template you have never filled in is
theory; a completed assessment on a real system is the proof of competence for this
tier. This is mostly writing and reasoning, with one runnable fairness check.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25.

**Prerequisite:** you finished the Tier 12 BUILD (you have `~/governance-toolkit/`
with the twelve templates and `fairness_check.py`). You have read Concepts 12.4. You
remember the Tier 7 assistant's shape: RAG over English + French documents, pgvector,
Claude plus an alternative model, authentication, role-based and document-level
permissions, citations, audit logs.

**Goal:** produce a completed, signed impact assessment for the Tier 7 assistant,
with a real fairness measurement attached, and a written go / no-go recommendation.

---

## Step 1: Set up the working folder

On your **lab server**, as **ec2-user**:

```bash
mkdir -p ~/use-impact-assessment
```

`mkdir -p` makes the folder safely. Move into it:

```bash
cd ~/use-impact-assessment
```

`cd` changes into it.

Expected output (yours will differ):

```
[ec2-user@lab-server use-impact-assessment]$
```

---

## Step 2: Copy the impact-assessment template to fill in

Still on your **lab server**, as **ec2-user**, copy the blank template from your
toolkit into this folder under a real filename:

```bash
cp ~/governance-toolkit/04-impact-assessment-template.md ./assistant-impact-assessment.md
```

`cp` copies the source (first path) to the destination (second path). Confirm it
copied:

```bash
ls
```

Expected output:

```
assistant-impact-assessment.md
```

---

## Step 3: Fill in the assessment against the Tier 7 assistant

Open your working copy. Still on your **lab server**, as **ec2-user**:

```bash
vi assistant-impact-assessment.md
```

Press `i` to enter insert mode and work through every section, answering for the
real Tier 7 assistant. Do not skip a section - a section you cannot answer is a
finding. Use the guidance below as you fill each one. When done, press `Esc`, type
`:wq` and press Enter to save and quit.

Guidance for each section, applied to the assistant:

- **System summary:** a bilingual (English/French) retrieval assistant that answers
  staff questions from an internal document store, with citations and per-document
  access control.
- **Affected people:** directly, the staff who ask questions and rely on answers;
  indirectly, anyone described in the documents, and customers affected by decisions
  staff make using the answers.
- **Intended benefits:** faster, cited answers from internal knowledge; less time
  hunting documents. State how you would measure it (time-to-answer, satisfaction).
- **Possible harms:** a confidently wrong (hallucinated) answer staff act on;
  surfacing a document a user should not see (permission failure); a French-language
  answer of lower quality than English (inclusion gap); over-reliance / deskilling.
- **Data sources:** the ingested document corpus - who owns it, is it accurate, is it
  representative across both languages, and do you have the right to index it.
- **Bias:** could answer quality differ by language or department? Note that quality
  disparity between English and French is a fairness/inclusion issue. Record how you
  will measure it - you will compute one number in Step 4.
- **Human oversight:** posture is "human on the loop" for general Q&A (staff judge the
  cited answer); if the assistant ever drives a decision about a person, that use is
  high-risk and needs human in the loop. Name the owner.
- **Security:** link to your Tier 11 threat model - prompt injection via ingested
  documents, access-control bypass, data poisoning. State the controls.
- **Privacy:** personal data may appear in documents and in logs. State minimization,
  retention, deletion, and whether any model provider trains on the data.
- **Complaints and appeals:** how a user reports a wrong or improperly disclosed
  answer, and how it is reviewed.
- **Monitoring:** groundedness/citation accuracy, permission-bypass alerts, per-
  language quality, safety violations - how often reviewed.
- **Decommissioning:** how the index, embeddings, logs, and access are torn down
  safely if the assistant is retired.
- **Decision:** residual risk and a recommendation (proceed / with conditions / no).

---

## Step 4: Attach a real fairness/quality measurement

Governance says "measure fairness," so measure it rather than asserting it. Here you
quantify whether answer quality is balanced across the two languages using a small
evaluation table. If you already have a Tier 7 evaluation golden set, use those
scores; otherwise this stand-in shows the method.

First set up a virtual environment. Still on your **lab server**, as **ec2-user**, in
`~/use-impact-assessment`:

```bash
python3.12 -m venv .venv
```

```bash
source .venv/bin/activate
```

Your prompt now shows `(.venv)`. Install pandas:

```bash
pip install pandas
```

`pip install` fetches the package. Confirm:

```bash
pip list | grep -i pandas
```

Expected output (yours will differ):

```
pandas   2.2.2
```

---

## Step 5: Write the language-parity check

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
vi language_parity.py
```

Press `i` and type (or paste):

```python
"""
Language-parity check for the bilingual assistant.

Reads per-question groundedness scores tagged by language and reports the
mean score per language and the parity ratio (lower / higher). A ratio well
below 1.0 means one language is being served worse - an inclusion/fairness
finding for the impact assessment.

Replace the sample rows below with your real Tier 7 evaluation results.
"""
import pandas as pd

# Sample evaluation results: each row is one golden-set question.
# groundedness is 0..1 (1 = fully grounded in cited sources).
data = [
    {"language": "en", "groundedness": 0.92},
    {"language": "en", "groundedness": 0.88},
    {"language": "en", "groundedness": 0.90},
    {"language": "en", "groundedness": 0.85},
    {"language": "fr", "groundedness": 0.74},
    {"language": "fr", "groundedness": 0.70},
    {"language": "fr", "groundedness": 0.68},
    {"language": "fr", "groundedness": 0.72},
]
df = pd.DataFrame(data)

print("=== LANGUAGE-PARITY CHECK: bilingual assistant ===")
means = df.groupby("language")["groundedness"].mean()
for lang, m in means.items():
    print(f"  {lang}: mean groundedness = {m:.3f}  (n={int((df.language==lang).sum())})")

lower = means.min()
higher = means.max()
ratio = lower / higher if higher > 0 else float("nan")
print()
print(f"Parity ratio (lower/higher): {ratio:.3f}")
if ratio < 0.90:
    print("FINDING: one language is served materially worse. Record this as an")
    print("inclusion/fairness harm in the impact assessment and plan remediation")
    print("(better French retrieval, French-specific evaluation, more FR content).")
else:
    print("OK: languages are within 10% on this set. Still document the result.")
```

Press `Esc`, type `:wq` and press Enter to save and quit.

---

## Step 6: Run the parity check

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python language_parity.py
```

Expected output (yours will differ):

```
=== LANGUAGE-PARITY CHECK: bilingual assistant ===
  en: mean groundedness = 0.887  (n=4)
  fr: mean groundedness = 0.710  (n=4)

Parity ratio (lower/higher): 0.800
FINDING: one language is served materially worse. Record this as an
inclusion/fairness harm in the impact assessment and plan remediation
(better French retrieval, French-specific evaluation, more FR content).
```

Read the result: French answers score materially lower than English. That is a
concrete inclusion finding - exactly the kind of measured evidence the "bias"
section of your assessment demands. Paste this number into that section, and add the
remediation to your monitoring plan.

Leave the environment:

```bash
deactivate
```

`deactivate` exits the venv; the `(.venv)` prefix disappears.

---

## Step 7: Record the finding in the assessment and decide

Reopen the assessment. Still on your **lab server**, as **ec2-user**:

```bash
vi assistant-impact-assessment.md
```

In the **bias** section, record the parity ratio and the finding. In **monitoring**,
add "track per-language groundedness monthly; act if parity ratio drops below 0.90."
Then complete the **Decision** block: given the French quality gap, a defensible
recommendation is "proceed with conditions" - ship for English, treat French as
limited until parity improves, and monitor. Press `Esc`, type `:wq`, Enter.

This is the whole competence: you took a real system, ran it through your own
template, measured a real fairness number, found a real problem, and made a
defensible, documented recommendation instead of a hopeful one.

---

## Step 8: Verify your deliverable

Still on your **lab server**, as **ec2-user**, in `~/use-impact-assessment`:

```bash
ls assistant-impact-assessment.md language_parity.py
```

Expected output:

```
assistant-impact-assessment.md  language_parity.py
```

Confirm you actually filled the template in (no leftover placeholders in the bias
section):

```bash
grep -c "ATTACH / SUMMARIZE" assistant-impact-assessment.md
```

`grep -c` counts matching lines. If you replaced the placeholder with your real
number, this prints `0`.

Expected output:

```
0
```

---

## What you produced and why it matters

- A completed, signed impact assessment for a real system, not a blank template.
- A measured fairness/inclusion finding (language parity), because governance must
  produce numbers, not assertions.
- A defensible "proceed with conditions" recommendation - the deliverable a client
  and a regulator will accept, and the proof of competence for this tier.

Prof. Happy (SUTA Labs)
