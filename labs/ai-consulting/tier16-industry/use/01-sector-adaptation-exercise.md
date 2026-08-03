# USE: Adapting Your Assistant and Governance Toolkit to a Sector

**Tier 16 - USE phase.** In this exercise you take two things you already built - your Tier 7 RAG assistant and your Tier 12 governance toolkit - and adapt them to one sector's real constraints. The worked example uses **public sector** (public records + accessibility + appeals), because it exercises the hardest constraints. Repeat the same method for your second sector.

**Validated on:** consulting-artifact review, 2026-07-25. Mostly writing and configuration reasoning; light code changes to the assistant.

**Prerequisite:** You have your Tier 7 assistant and Tier 12 governance toolkit in hand, and you have read the Tier 16 Concepts module for your sector.

**Goal:** Produce a sector-adapted assistant configuration and a sector-adapted governance policy, so your generic capabilities become a credible sector offering.

---

## The method: constraint-by-constraint

Do not rebuild. For each sector constraint, ask three questions:
1. What does this constraint require?
2. What in my current assistant or toolkit does not meet it?
3. What is the smallest change that closes the gap?

Write the answers down. That table IS the adaptation.

---

## Worked example: public sector (records + accessibility + appeals)

### Constraint 1: Public records - access control maps to records classification

- **Requires:** the assistant must never surface a record to a user who is not cleared for its classification, and must respect redaction.
- **Gap:** your Tier 7 assistant filters by user role, but roles are generic ("staff", "admin"), not tied to records classification (public / internal / restricted).
- **Smallest change:** map each document's metadata to a classification level; extend the retrieval filter to compare the user's clearance to the document's classification; refuse and log when they do not match.

Configuration change (concept, in your assistant's document metadata):

```
# each ingested document gets a classification tag
classification: public | internal | restricted
```

Retrieval rule (concept):

```
retrieve only where document.classification <= user.clearance
```

### Constraint 2: Accessibility

- **Requires:** the assistant's interface meets a recognized accessibility standard (commonly WCAG). Screen-reader compatible, keyboard-navigable, sufficient contrast, no information conveyed by color alone.
- **Gap:** your assistant's front end was built for function, not audited for accessibility.
- **Smallest change:** run an accessibility audit against the standard; fix contrast, labels, focus order, and alt text; document the conformance level. Accessibility is a procurement gate, so this is not optional.

### Constraint 3: Appeals

- **Requires:** for any answer that informs a consequential decision, you must be able to reconstruct, after the fact, exactly what the system returned and on what sources - and a human must be able to overturn it.
- **Gap:** your assistant logs conversations, but not in an appeal-grade, reconstructable way (which document versions, which citations, which model version).
- **Smallest change:** extend logging to store, per response: the user, the query, the retrieved chunks with document IDs and versions, the citations shown, the model version, and the timestamp. Ensure these logs are retained and query-able for the legally required period.

Appeal-grade log record (concept):

```
{
  "timestamp": "...",
  "user_id": "...",
  "query": "...",
  "retrieved": [{"doc_id": "...", "version": "...", "chunk": "..."}],
  "citations_shown": ["..."],
  "model_version": "...",
  "human_decision": null   // filled in by the accountable officer
}
```

---

## Step-by-step: do this on your lab server

### Step 1: Log in and open your assistant project

On your **lab server**, as **ec2-user**:

```
cd ~/project7-enterprise-knowledge-assistant
```

The `cd` command changes directory into your Tier 7 assistant.

### Step 2: Write the adaptation table

On your **lab server**, as **ec2-user**:

```
vi SECTOR-ADAPTATION.md
```

`vi` opens the editor. Fill in the three-column table (Constraint / Requires / Smallest change) for every constraint in your sector's Concepts module. Save and quit with `:wq`.

### Step 3: Apply the classification-aware retrieval change

Edit your retrieval code to filter by classification as well as role. Add a `classification` field to your document metadata and a `clearance` field to your users, then compare them at retrieval time. Keep the change small and test it: a restricted document must not appear for a public-clearance user.

### Step 4: Extend logging to appeal-grade

Edit your logging so every response stores the full reconstructable record shown above. Verify by asking a question and confirming the log contains the document versions and citations.

### Step 5: Adapt the governance policy

Copy your Tier 12 governance policy and edit it for the sector: add the sector's hard rules, its risk classification, its data-handling rules, and its appeal/incident process. Save as `governance-<sector>.md`.

---

## Deliverable of this exercise

Two files per sector:
- `SECTOR-ADAPTATION.md` - the constraint-by-constraint table plus the applied changes.
- `governance-<sector>.md` - your governance toolkit adapted to the sector.

Plus a working assistant whose retrieval respects classification and whose logs are appeal-grade.

---

## Why this matters

Clients do not buy generic AI. They buy someone who understands their constraints. This exercise is how you turn "I built a RAG assistant once" into "I have deployed governed, accessible, appealable AI for the public sector." That sentence is the sale.

---

Prof. Happy (SUTA Labs)
