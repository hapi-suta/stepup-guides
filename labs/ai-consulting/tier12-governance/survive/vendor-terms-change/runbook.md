# SURVIVE: Vendor Changes Terms / Deprecates a Model

> **How this scenario is assessed:** this is a document- and decision-based
> scenario, not a script-tested one. There is no `inject.sh` or `validate.sh`.
> You are assessed by review: you produce the written deliverables listed at the
> end (a vendor-change impact note, a decision, and an updated vendor record), and
> a second person - your instructor or a peer - checks them against the checklist.
> This mirrors real consulting, where the "test" is whether a client would act on
> your recommendation.

## Scenario

You manage the AI vendor for a client's bilingual knowledge assistant. On a Tuesday
the vendor sends two notices at once:

1. They are **deprecating the model version** your assistant is pinned to. It will
   stop working in 60 days; you must move to a newer version.
2. They are **updating their terms of service** so that, on the standard tier,
   customer prompts may now be used to improve their models unless you upgrade to a
   more expensive enterprise tier that preserves the no-training guarantee.

Your client handles personal data and is in a regulated, data-residency-sensitive
sector. Leadership asks you: "Do we just accept this? Do we pay more? Do we leave?"

Your job in this SURVIVE scenario:
1. Detect the significance of the change (it is not routine).
2. Diagnose the impact against your original vendor assessment and the client's
   requirements.
3. Resolve it: trigger the vendor-management and exit review, decide, and document.

This runbook uses the SUTA 3-layer structure:
- Layer 1: Detect
- Layer 2: Diagnose
- Layer 3: Resolve and document

Governance context: this exercises the vendor-management policy (Concepts 12.5), the
vendor assessment (Concepts 12.6), and NIST AI RMF (Govern - third parties; Manage -
respond to a changed risk). A vendor change is precisely when an untested exit path
bites - so this is where the assessment work you did earlier pays off.

---

## Layer 1: Detect (the change is not routine)

Not every vendor email is an incident. This one is, because it changes two things you
assessed and contracted around:

- **Model deprecation** changes behaviour and forces a migration on a deadline. A new
  model version can shift accuracy, tone, groundedness, and cost (this is model drift
  from the provider side, Tier 10).
- **Terms change on customer-data usage** changes your privacy posture. "May use your
  prompts to improve models" on a client with personal data is potentially a
  dealbreaker - the exact area you weighted heavily in the vendor questionnaire.

Detection rule: any vendor change to **data usage, data residency, retention, model
version, pricing, or security posture** triggers a re-assessment. Log this one and
open a vendor-change review.

### What to gather
- The vendor's notice(s), dated.
- Your original vendor assessment for this vendor (the completed questionnaire).
- The client's hard requirements (for this client: no training on our data, in-region
  processing, and a workable exit path).

---

## Layer 2: Diagnose (impact against the assessment and requirements)

Re-open your original vendor assessment and compare, area by area, what changed.

### Step 2.1 - Re-score the affected areas
Two areas move:

- **Customer-data usage:** was "no training on our data" on the tier you bought. The
  new standard terms break that guarantee unless you pay for enterprise. For a client
  with personal data, this is a **dealbreaker** on the standard tier. Score drops to 1.
- **Model updates:** the vendor is deprecating your pinned version with 60 days notice.
  Assess whether 60 days is enough to migrate, evaluate the new version, and re-run
  your golden set. If your original assessment assumed you could pin versions
  indefinitely, that assumption is now false - a real risk to record.

### Step 2.2 - Check the client's requirements against the new reality
Walk the hard requirements:

- No training on our data: **fails** on the standard tier. Passes only if the client
  pays for enterprise.
- In-region processing: unchanged? Confirm the notice does not also move data. If it
  does, that is a second dealbreaker.
- Workable exit: is the export path you assessed still available and tested? If you
  never tested it, that is a gap this event just exposed.

### Step 2.3 - Frame the real decision
The change forces one of three paths. Name them plainly for leadership:

1. **Pay up:** move to the enterprise tier to keep the no-training guarantee, and
   migrate to the new model version within the 60 days. Higher cost; lowest disruption.
2. **Accept the standard terms:** cheaper, but the client's data may train the vendor's
   models. For a client with personal data in a regulated sector, this is almost
   certainly unacceptable - say so.
3. **Exit:** move to another provider. This is why you kept a model-provider abstraction
   (Tier 6) and assessed an exit path. Higher effort; removes the dependency.

The diagnosis is not "which is cheapest" - it is "which satisfies the client's
non-negotiable requirements at acceptable cost and risk."

---

## Layer 3: Resolve and document

Governance resolves vendor changes with a decision AND a paper trail. Produce the
three deliverables below.

### Step 3.1 - Write the vendor-change impact note

On your lab server, as ec2-user, create a working folder and the note:

```
mkdir -p ~/survive-vendor-change
```

```
cd ~/survive-vendor-change
```

Open the note in vi:

```
vi vendor-change-impact-note.md
```

Press `i` and write it. It must cover:
- What changed (model deprecation + data-usage terms), dated.
- Which vendor-assessment areas moved and their new scores.
- Which client requirements are now at risk (call out the dealbreaker).
- The three options (pay up / accept / exit) with cost, risk, and effort for each.

Press `Esc`, type `:wq`, Enter.

### Step 3.2 - Record the decision and required actions

Still on your lab server, as ec2-user:

```
vi vendor-change-decision.md
```

Press `i` and write the recommendation. A defensible decision for this client:
"Recommend Option 1 (enterprise tier) to preserve the no-training guarantee and
in-region processing; migrate to the new model version and re-run the golden-set
evaluation before cutover; in parallel, test the exit path so Option 3 stays viable if
the vendor changes terms again." Include: decision, owner, deadline (before the 60-day
cutoff), and the contract terms to re-confirm in writing (no-training, residency,
future-deprecation notice period). Press `Esc`, type `:wq`, Enter.

### Step 3.3 - Update the vendor record

Still on your lab server, as ec2-user:

```
vi vendor-record-update.md
```

Press `i` and note the changes to the vendor's entry: new tier, new model version,
re-assessment date, the dealbreaker that was triggered and how it was resolved, and the
date the exit path was tested. This keeps the vendor assessment a living document, not
a one-time form. Press `Esc`, type `:wq`, Enter.

### Step 3.4 - Self-check against the review checklist

Since there is no validator, check your own work against this list before submitting
for review. You pass when every box is a clear "yes":

- [ ] The impact note names both changes and dates them.
- [ ] The re-scored areas (customer-data usage, model updates) are explicit, with the
      dealbreaker called out.
- [ ] The client's hard requirements are each checked against the new terms.
- [ ] All three options (pay up / accept / exit) are presented with cost, risk, effort.
- [ ] A clear recommendation is made, with an owner and a deadline before the 60-day
      cutoff.
- [ ] The exit path is addressed (tested or scheduled to be tested), not assumed.
- [ ] The vendor record is updated with the re-assessment.

Hand these three documents to your instructor or a peer for review. If they can read
them and know exactly what the client should do and why, you pass.

---

## Key takeaways

- A vendor change to data usage, residency, retention, model version, pricing, or
  security is not routine - it triggers a re-assessment and a documented decision.
- Compare the change against your original vendor assessment and the client's
  non-negotiable requirements. A broken no-training guarantee for a client with
  personal data is a dealbreaker, not a line item.
- Frame the decision as pay up / accept / exit, and choose on requirements and risk,
  not just cost.
- The exit path must be real and tested. A vendor change is exactly when an untested
  exit path fails you - which is why you kept a provider abstraction and assessed the
  exit up front.
- Document everything: an impact note, a decision with owner and deadline, and an
  updated vendor record. In consulting, the decision and its paper trail are the
  deliverable.

Prof. Happy (SUTA Labs)
