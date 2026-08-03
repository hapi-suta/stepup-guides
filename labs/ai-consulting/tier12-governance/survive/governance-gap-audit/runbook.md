# SURVIVE: Governance Gap Audit - A Deployed System With No Governance

## Scenario

You are brought into an organization to review its AI governance. They hand you
their AI system inventory and assure you "everything is covered." While walking the
inventory you find a system in production that scores citizen benefit eligibility -
a high-risk, life-affecting decision - with no impact assessment, no human-oversight
plan, and no named owner. It is live right now, making decisions about real people,
with no governance behind it.

Your job in this SURVIVE scenario:
1. Detect the gap by auditing the inventory.
2. Diagnose why it is serious (high-risk, consequential decision, no oversight).
3. Fix it by producing the missing artifacts and closing the inventory entry.

The scenario has already been injected into `~/survive-governance-gap`.

This runbook uses the SUTA 3-layer structure:
- Layer 1: Detect (what is the symptom)
- Layer 2: Diagnose (what is the root cause)
- Layer 3: Fix and verify

Governance context: a deployed high-risk system with no impact assessment violates
both NIST AI RMF (Map/Manage) and ISO/IEC 42001 (planning and operational controls).
This is exactly the finding an auditor or regulator would escalate first.

---

## Layer 1: Detect (the symptom)

### Step 1.1 - Go to the working directory

On your lab server, as ec2-user:

```
cd ~/survive-governance-gap
```

`cd` means "change directory". This moves you into the folder holding the injected
inventory and audit tool.

### Step 1.2 - See what is there

Still on your lab server, as ec2-user:

```
ls -l
```

`ls` lists files; `-l` shows the long format (size, date, name).

Expected output (yours will differ):

```
-rw-r--r--. 1 ec2-user ec2-user  520 Jul 25 15:10 ai_system_inventory.csv
-rw-r--r--. 1 ec2-user ec2-user 1180 Jul 25 15:10 audit_inventory.py
```

### Step 1.3 - Read the inventory

Still on your lab server, as ec2-user:

```
cat ai_system_inventory.csv
```

`cat` prints the file to the screen. Each row is one AI system with its owner, risk
class, status, and whether it has an impact assessment and oversight plan.

Expected output (yours will differ):

```
id,name,purpose,owner,vendor_or_inhouse,risk_class,status,impact_assessment,oversight_plan
AI-001,Meeting Summarizer,...,ops-lead,vendor,minimal,production,not-required,not-required
AI-002,Support Chatbot,...,support-lead,vendor,limited,production,IA-2026-02-11.md,oversight-AI-002.md
AI-003,Benefits Eligibility Assistant,...,MISSING,in-house,high,production,MISSING,MISSING
AI-004,Doc Search,...,eng-lead,in-house,limited,pilot,IA-2026-05-01.md,oversight-AI-004.md
```

### Step 1.4 - Run the audit tool

Still on your lab server, as ec2-user:

```
python3 audit_inventory.py
```

`python3 audit_inventory.py` runs the read-only audit. It flags any production system
above minimal risk that is missing an owner, an impact assessment, or an oversight
plan. No virtual environment is needed - it uses only the Python standard library.

Expected output (yours will differ):

```
=== GOVERNANCE-GAP AUDIT ===
GAP: AI-003 (Benefits Eligibility Assistant) [risk=high]
       - no named owner
       - no impact assessment
       - no human-oversight plan

1 system(s) with governance gaps. Remediate before this passes.
```

Symptom confirmed: AI-003 is the gap. Note the audit exited non-zero (a failure) -
that is the machine telling you the estate is not compliant.

---

## Layer 2: Diagnose (the root cause)

### Step 2.1 - Understand why this one is serious

AI-003 is not just missing paperwork. Walk the risk logic from Concepts 12.4:

- It makes a **consequential decision about a person** (benefit eligibility - money
  and access to a service). That alone forces a high-risk classification.
- It is **in production**, affecting real applicants now.
- It has **no human-oversight plan**, so there is no defined way for a person to
  review or override a wrong denial, and **no appeals path**.
- It has **no named owner**, so no one is accountable when it is wrong.

The root cause is a process failure: the system was deployed without passing the AI
project approval workflow (Concepts 12.5), which would have required an impact
assessment and an oversight plan before production. This is how "shadow" or
ungoverned high-risk AI ends up live.

### Step 2.2 - Confirm no artifacts exist

Still on your lab server, as ec2-user:

```
ls *AI-003* 2>/dev/null || echo "no AI-003 artifacts exist yet"
```

This looks for any file naming AI-003. The `2>/dev/null || echo ...` prints a friendly
message if none exist.

Expected output (yours will differ):

```
no AI-003 artifacts exist yet
```

Root cause confirmed: the governance artifacts for a live high-risk system simply do
not exist. That is the gap you must close.

---

## Layer 3: Fix and verify

You remediate by producing the two missing artifacts (impact assessment and
human-oversight plan) and updating the inventory to name an owner and reference them.
Use your Tier 12 toolkit templates as the starting point.

### Step 3.1 - Produce the impact assessment for AI-003

If your governance toolkit is on this server, copy the template. Still on your lab
server, as ec2-user:

```
cp ~/governance-toolkit/04-impact-assessment-template.md ./AI-003-impact-assessment.md
```

`cp` copies the blank template to a file named for AI-003. (If the toolkit is not on
this box, create the file with `vi AI-003-impact-assessment.md` and write the sections
from memory - affected people, harms, bias, oversight, appeals, monitoring.)

Now fill it in for the benefits assistant. Open it:

```
vi AI-003-impact-assessment.md
```

Press `i` and complete every section for a benefits-eligibility system: affected
people are applicants; possible harms include wrongful denial of a benefit; bias
against protected groups is a real risk (measure disparate impact); oversight must be
human in the loop; there MUST be an appeals path; monitoring must include fairness.
Press `Esc`, type `:wq`, Enter.

### Step 3.2 - Produce the human-oversight plan for AI-003

Still on your lab server, as ec2-user:

```
cp ~/governance-toolkit/08-human-oversight-plan.md ./AI-003-oversight-plan.md
```

(Or create it with `vi AI-003-oversight-plan.md` if the toolkit is not present.)

Open it:

```
vi AI-003-oversight-plan.md
```

Press `i` and complete it for a high-risk system: posture is **human in the loop** (a
caseworker approves or reviews every eligibility decision before it takes effect);
name who reviews, who can override, who can stop the system; describe the appeals
path. Press `Esc`, type `:wq`, Enter.

### Step 3.3 - Update the inventory

Now close the inventory entry so AI-003 has an owner and references the two artifacts.
Still on your lab server, as ec2-user:

```
vi ai_system_inventory.csv
```

Press `i` and edit the AI-003 line. Replace each `MISSING` with a real value:
- owner: a real role, for example `benefits-program-lead`
- impact_assessment: `AI-003-impact-assessment.md`
- oversight_plan: `AI-003-oversight-plan.md`

The corrected line should look like (one line, no `MISSING`):

```
AI-003,Benefits Eligibility Assistant,Score citizen benefit eligibility,benefits-program-lead,in-house,high,production,AI-003-impact-assessment.md,AI-003-oversight-plan.md
```

Press `Esc`, type `:wq`, Enter to save and quit.

### Step 3.4 - Re-run the audit

Still on your lab server, as ec2-user:

```
python3 audit_inventory.py
```

Now that the row is complete, the audit should find no gaps.

Expected output (yours will differ):

```
=== GOVERNANCE-GAP AUDIT ===
No governance gaps found. All production systems above minimal risk
have an owner, an impact assessment, and a human-oversight plan.
```

### Step 3.5 - Verify with the validator

Still on your lab server, as ec2-user, run the scenario validator. The exact path
depends on where this scenario was placed, for example:

```
bash ~/survive-governance-gap/validate.sh
```

If the validator lives with the lab content, run it from there instead. It checks
that both artifacts exist, the inventory row is clean, and the audit passes.

Expected output (yours will differ):

```
PASS: impact assessment for AI-003 exists (AI-003-impact-assessment.md)
PASS: human-oversight plan for AI-003 exists (AI-003-oversight-plan.md)
PASS: AI-003 inventory row has no MISSING fields
PASS: audit_inventory.py now reports no governance gaps
ALL CHECKS PASSED
```

---

## Key takeaways

- Governance gaps hide in the inventory. The inventory is the first thing you audit,
  because you cannot govern what you have not listed.
- A high-risk, production system with no impact assessment and no oversight plan is a
  top-severity finding - it makes consequential decisions about people with no
  accountability and no appeals.
- The root cause is almost always a skipped approval workflow. The durable fix is to
  route every AI system through intake -> risk classification -> approval before
  production, not just to patch the one you found.
- Remediation is concrete: produce the missing artifacts, name an owner, and update
  the inventory so the audit passes. "We'll get to it" is not remediation.

Prof. Happy (SUTA Labs)
