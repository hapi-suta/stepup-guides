# BUILD: Project 12 - The AI Governance Toolkit

**Tier 12 - the governance capstone.** You will assemble a complete, reusable **AI Governance Toolkit**: the set of documents a consultant carries into any engagement to govern AI against NIST AI RMF and ISO/IEC 42001. Unlike earlier tiers, most of this project is **artifacts** - policies, templates, matrices, and forms - not code. That is exactly what the work is: an AI Strategy, Governance and Implementation Consultant is paid to produce these and apply them.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25. The one runnable piece (a fairness metric computed with pandas + scikit-learn) was tested and its real output is shown.

**Prerequisite:** you read all of Tier 12 Concepts (12.1 principles, 12.2 NIST AI RMF, 12.3 ISO/IEC 42001, 12.4 impact assessments, 12.5 policy, 12.6 vendor assessment). You are logged into your lab server and can edit files with vi.

**What you build:** a folder `governance-toolkit/` containing twelve deliverables, plus one small Python fairness-check script (the one place governance needs a real number). Ready-made template bodies are provided alongside this guide in `toolkit-templates/` - you copy them in, read them, and adapt them. The goal is that you understand every artifact well enough to defend it in front of a board.

The twelve deliverables:

1. AI policy
2. AI use-case intake form
3. AI risk-classification matrix
4. AI impact-assessment template
5. Vendor questionnaire
6. Model card
7. Data sheet
8. Human-oversight plan
9. AI incident-report template
10. AI system inventory
11. AI project approval workflow
12. Executive dashboard

---

## Step 1: Create the toolkit folder

On your **lab server**, as **ec2-user**, make the working folder:

```bash
mkdir -p ~/governance-toolkit
```

`mkdir` makes a directory. The `-p` flag means "create parents if needed and do not error if it already exists," so this is safe to run twice.

Move into it:

```bash
cd ~/governance-toolkit
```

`cd` changes into the folder so every file you create lands here.

Expected output (yours will differ):

```
[ec2-user@lab-server governance-toolkit]$
```

The prompt ending in `governance-toolkit` confirms you are inside the folder.

---

## Step 2: Confirm the template bodies are available

The ready-made template bodies live next to this guide, in the lab's `build/toolkit-templates/` folder. The exact path on your server depends on where this lab was placed, but you can find it. Still on your **lab server**, as **ec2-user**:

```bash
find ~ / -type d -name toolkit-templates 2>/dev/null | head -1
```

`find` searches for a directory named `toolkit-templates`. The `2>/dev/null` hides permission-denied noise; `head -1` shows the first match. Note the path it prints - call it `TEMPLATES`.

Expected output (yours will differ):

```
/home/ec2-user/labs/ai-consulting/tier12-governance/build/toolkit-templates
```

Save it to a shell variable so the copy commands below are short. Replace the path with the one you found:

```bash
TEMPLATES=/home/ec2-user/labs/ai-consulting/tier12-governance/build/toolkit-templates
```

Confirm it holds the twelve templates:

```bash
ls "$TEMPLATES"
```

`ls` lists the folder. You should see twelve markdown files.

Expected output (yours will differ):

```
01-ai-policy.md                  07-data-sheet.md
02-use-case-intake-form.md       08-human-oversight-plan.md
03-risk-classification-matrix.md 09-incident-report-template.md
04-impact-assessment-template.md 10-ai-system-inventory.md
05-vendor-questionnaire.md       11-project-approval-workflow.md
06-model-card.md                 12-executive-dashboard.md
```

If `find` returns nothing, ask your instructor for the template path. You can still build every artifact by hand from the Concepts docs, but copying the vetted templates is faster and is the point of a reusable toolkit.

---

## Step 3: Copy the twelve templates into your toolkit

Still on your **lab server**, as **ec2-user**, in `~/governance-toolkit`:

```bash
cp "$TEMPLATES"/*.md ~/governance-toolkit/
```

`cp` copies files. `"$TEMPLATES"/*.md` matches all twelve markdown templates; the destination is your toolkit folder. Confirm they landed:

```bash
ls ~/governance-toolkit
```

Expected output (yours will differ):

```
01-ai-policy.md                  07-data-sheet.md
02-use-case-intake-form.md       08-human-oversight-plan.md
03-risk-classification-matrix.md 09-incident-report-template.md
04-impact-assessment-template.md 10-ai-system-inventory.md
05-vendor-questionnaire.md       11-project-approval-workflow.md
06-model-card.md                 12-executive-dashboard.md
```

You now have the full toolkit skeleton. The next steps walk you through each artifact so you understand it - do not just own the files, know them.

---

## Step 4: Read and understand the AI policy (deliverable 1)

Open the policy so you know what you are handing a client. Still on your **lab server**, as **ec2-user**:

```bash
vi 01-ai-policy.md
```

`vi` opens the file. Read it top to bottom. Notice it follows the policy skeleton from Concepts 12.5: purpose, scope, definitions, policy statements, roles, procedures, enforcement, review. Notice the placeholders in square brackets like `[ORGANIZATION]` and `[POLICY OWNER ROLE]` - those are what you fill in per client.

To leave vi without changing anything, type `:q!` and press Enter.

Now personalize it for a practice client. Reopen it:

```bash
vi 01-ai-policy.md
```

Use vi search to jump to the first placeholder: press `Esc`, type `/[ORGANIZATION]` and press Enter. Press `i` to enter insert mode and replace it with a practice name, for example `Riverside County`. Do the same for the other bracketed placeholders. When done, press `Esc`, type `:wq` and press Enter to save and quit.

This is the core consulting motion: a vetted template, adapted per client, not written from scratch each time.

---

## Step 5: Read the intake form, risk matrix, and approval workflow (deliverables 2, 3, 11)

These three work together: a new AI idea comes in on the **intake form**, gets a risk class from the **risk-classification matrix**, and moves through the **approval workflow**. Read them in that order.

Still on your **lab server**, as **ec2-user**:

```bash
vi 02-use-case-intake-form.md
```

Read it. It is the on-ramp: a short form anyone in the organization fills in to propose an AI use case (what problem, what data, who is affected, expected benefit). Quit with `:q!` and Enter.

```bash
vi 03-risk-classification-matrix.md
```

Read it. It turns an intake into a risk class (minimal / limited / high / unacceptable) using severity of harm and scale of exposure, exactly as in Concepts 12.4. Quit with `:q!` and Enter.

```bash
vi 11-project-approval-workflow.md
```

Read it. It defines who approves what at each risk class, and requires an impact assessment for high-risk cases. Quit with `:q!` and Enter.

Together these three are the governance "front door" that stops ungoverned AI from appearing (shadow AI).

---

## Step 6: Read the impact-assessment template (deliverable 4)

This is the most important artifact. Still on your **lab server**, as **ec2-user**:

```bash
vi 04-impact-assessment-template.md
```

Read every section: affected people, intended benefits, possible harms, data sources, bias, human oversight, security, privacy, complaints and appeals, monitoring, decommissioning. These are the sections from Concepts 12.4. You will fill this in for real against your Tier 7 assistant in the USE phase - so read it now with that system in mind.

Quit with `:q!` and Enter.

---

## Step 7: Read the vendor questionnaire, model card, and data sheet (deliverables 5, 6, 7)

These three document the AI supply chain: who you buy from (vendor questionnaire), the model you ship (model card), and the data behind it (data sheet).

Still on your **lab server**, as **ec2-user**:

```bash
vi 05-vendor-questionnaire.md
```

Read it. Every question maps to an area in Concepts 12.6 (customer-data usage, retention, residency, subprocessors, exit, pricing risk, and more). You score a real vendor with it in USE. Quit with `:q!` and Enter.

```bash
vi 06-model-card.md
```

Read it. A model card is the "label on the box" (transparency, Concepts 12.1): intended use, out-of-scope use, training data summary, evaluation results, limitations, and fairness considerations. Quit with `:q!` and Enter.

```bash
vi 07-data-sheet.md
```

Read it. A data sheet (a "datasheet for datasets") documents where the data came from, how it was collected, what it contains, its known biases, consent, and retention. Quit with `:q!` and Enter.

---

## Step 8: Read the human-oversight plan and incident-report template (deliverables 8, 9)

Still on your **lab server**, as **ec2-user**:

```bash
vi 08-human-oversight-plan.md
```

Read it. It states the oversight posture (in the loop / on the loop / in command), who reviews, who can override, and who can stop the system - for a specific AI system. Quit with `:q!` and Enter.

```bash
vi 09-incident-report-template.md
```

Read it. It is what someone fills in when the AI misbehaves (a biased output, a leak, a harmful answer): what happened, when, who was affected, severity, immediate action, root cause, remediation, and lessons learned. You will run this end to end in the biased-output SURVIVE scenario. Quit with `:q!` and Enter.

---

## Step 9: Read the AI system inventory and executive dashboard (deliverables 10, 12)

These two are the "management view" - what AI do we run, and how healthy is our governance.

Still on your **lab server**, as **ec2-user**:

```bash
vi 10-ai-system-inventory.md
```

Read it. It is the living register of every AI system: name, owner, purpose, risk class, status, last impact assessment date, and vendor. NIST AI RMF's Govern function depends on this. Quit with `:q!` and Enter.

```bash
vi 12-executive-dashboard.md
```

Read it. It is the one-page summary for leadership: how many AI systems, by risk class, how many have current impact assessments, open incidents, and vendor risks. It rolls the whole toolkit up into numbers a board can act on. Quit with `:q!` and Enter.

---

## Step 10: Add the one runnable piece - a fairness check

Governance says "measure fairness." Here you actually do it. You will compute the **selection rate by group** and the **disparate-impact ratio** for a hiring-screen model, using pandas and scikit-learn on CPU. This is the number that turns "we think it is fair" into evidence for your impact assessment.

First create and activate a virtual environment. Still on your **lab server**, as **ec2-user**, in `~/governance-toolkit`:

```bash
python3.12 -m venv .venv
```

`-m venv` runs Python's built-in virtual-environment module; `.venv` is the folder it creates.

```bash
source .venv/bin/activate
```

`source` runs the activate script in your current shell. Your prompt now shows `(.venv)`.

Install the libraries:

```bash
pip install numpy pandas scikit-learn
```

`pip install` downloads the packages. `numpy` is math, `pandas` is table handling, `scikit-learn` gives us a simple model and metrics.

Confirm they installed:

```bash
pip list | grep -Ei "numpy|pandas|scikit-learn"
```

Expected output (yours will differ):

```
numpy         2.1.1
pandas        2.2.2
scikit-learn  1.5.2
```

---

## Step 11: Write the fairness-check script

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
vi fairness_check.py
```

Press `i` to enter insert mode, then type (or paste) the following:

```python
"""
Fairness check for a hiring-screen model.

Computes, per group:
  - selection rate: the fraction of applicants the model advances
  - disparate-impact ratio: least-favoured group's rate divided by the
    most-favoured group's rate.

The "four-fifths rule" (a common US guideline) flags possible adverse
impact when that ratio falls below 0.80. This is not legal advice; it is
a screening metric that tells you where to look.
"""
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression

rng = np.random.default_rng(42)
N = 2000

# Two groups, A and B, roughly equal in size.
group = rng.choice(["A", "B"], size=N)

# A "years of experience" feature. Suppose group B has, on average,
# slightly less recorded experience in THIS dataset - a data artifact,
# not a difference in true ability.
experience = np.where(
    group == "A",
    rng.normal(8, 3, size=N),
    rng.normal(6, 3, size=N),
).clip(0, None)

# True qualification does NOT depend on group; it depends on experience
# plus noise. We label the top ~40% as "qualified".
score = experience + rng.normal(0, 2, size=N)
qualified = (score > np.percentile(score, 60)).astype(int)

df = pd.DataFrame(
    {"group": group, "experience": experience, "qualified": qualified}
)

# Train a model that ONLY sees experience (a seemingly neutral feature).
# Because experience is correlated with group in this dataset, the model
# can still produce different selection rates across groups. Experience
# is acting as a PROXY variable.
X = df[["experience"]].values
y = df["qualified"].values
model = LogisticRegression().fit(X, y)
df["advanced"] = model.predict(X)

print("=== FAIRNESS CHECK: hiring-screen model ===")
rates = {}
for g, sub in df.groupby("group"):
    rate = sub["advanced"].mean()
    rates[g] = rate
    print(f"Group {g}: selection rate = {rate:.3f}  (n={len(sub)})")

worst = min(rates.values())
best = max(rates.values())
di_ratio = worst / best if best > 0 else float("nan")
print()
print(f"Disparate-impact ratio (min/max): {di_ratio:.3f}")
if di_ratio < 0.80:
    print("FLAG: ratio below 0.80 (four-fifths rule). Possible adverse")
    print("impact. Investigate the proxy variable (experience) and the")
    print("data, and record this in the impact assessment.")
else:
    print("OK: ratio at or above 0.80 on this screen. Still document it.")
```

Press `Esc` to leave insert mode, then type `:wq` and press Enter to save and quit.

---

## Step 12: Run the fairness check

Still on your **lab server**, as **ec2-user**, in the activated environment:

```bash
python fairness_check.py
```

This runs the script. It trains a tiny model on a "neutral" feature (experience) and measures the selection rate per group.

Expected output (yours will differ slightly by machine):

```
=== FAIRNESS CHECK: hiring-screen model ===
Group A: selection rate = 0.511  (n=998)
Group B: selection rate = 0.250  (n=1002)

Disparate-impact ratio (min/max): 0.488
FLAG: ratio below 0.80 (four-fifths rule). Possible adverse
impact. Investigate the proxy variable (experience) and the
data, and record this in the impact assessment.
```

Read what just happened: the model was never told the group. It only saw "years of experience." But because experience was correlated with group in the data, the model advanced group A at nearly twice the rate of group B. That is a **proxy variable** creating adverse impact, exactly the trap from Concepts 12.1 and 12.4. This single number is the kind of evidence your impact assessment's "bias" section demands - do not govern fairness you have not measured.

Leave the environment when done:

```bash
deactivate
```

`deactivate` exits the virtual environment; the `(.venv)` prefix disappears.

---

## Step 13: Verify the toolkit is complete

Still on your **lab server**, as **ec2-user**, in `~/governance-toolkit`:

```bash
ls -1 *.md | wc -l
```

`ls -1 *.md` lists the markdown files one per line; `wc -l` counts the lines. You should have twelve deliverables.

Expected output:

```
12
```

Confirm the fairness script is present too:

```bash
ls fairness_check.py
```

Expected output:

```
fairness_check.py
```

You now hold a complete, reusable AI Governance Toolkit plus a working fairness measurement. In USE you will apply two of these artifacts for real (an impact assessment on your Tier 7 assistant, and a vendor score). In SURVIVE you will exercise the governance-gap audit, the incident process, and the vendor-change review.

---

## What you built and why it matters

- Twelve governance deliverables, each mapping to a NIST AI RMF function and an ISO/IEC 42001 clause. This is the physical product a governance consultant sells.
- One runnable fairness check, because "measure fairness" must produce a number, and a proxy variable can create adverse impact even when the protected attribute is never used.
- The consulting motion: vetted templates, adapted per client, backed by real measurement - not documents written from scratch and not claims without evidence.

Prof. Happy (SUTA Labs)
