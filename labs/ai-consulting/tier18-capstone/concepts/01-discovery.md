# Concepts: Capstone Part 1 - Discovery

**Tier 18, Module 18.1** - understanding the client before you propose anything.

Discovery is where most engagements are won or lost. If you skip it and jump to building, you will build the wrong thing on top of unclean data with no accountability. This module covers the seven discovery activities and what each produces.

**The rule of discovery:** produce evidence, not impressions. Every discovery activity ends in a written artifact you could hand to the next consultant.

---

## The seven discovery activities

### 1. Stakeholder interviews
Talk to the people who will sponsor, use, be affected by, and be accountable for the system. For a public institution that means leadership (the sponsor), frontline staff (the users), the IT/security function, the legal/compliance function, and ideally a representative of the citizens served.

Produce: an interview log with, per stakeholder, their goals, fears, constraints, and what success looks like to them. Watch for the gap between what leadership wants ("an AI") and what staff actually need (find policy fast).

### 2. Process mapping
Map the real workflow the assistant will support - how staff currently find and use information - step by step, including the pain points and the workarounds. You cannot improve a process you have not drawn.

Produce: a current-state process map and a marked-up "where AI helps" version.

### 3. Document inventory
Catalog the corpus the assistant will draw on: how many documents, in what formats, in what languages, where they live, how current they are, and who owns them. Public-sector corpora are usually messy: scanned PDFs, mixed languages, duplicates, outdated versions.

Produce: a document inventory table (count, format, language, owner, freshness, location).

### 4. Data classification
Classify every document by sensitivity: public, internal, or restricted. This is the single most important discovery output for a public-sector build, because access control is impossible without it, and appeal and disclosure law depends on it. If records are unclassified, classifying them becomes a prerequisite project.

Produce: a classification of the corpus, or a plan to classify it if it is not already.

### 5. Technical review
Assess the existing environment: infrastructure, connectivity, databases, hosting constraints, and what the institution can and cannot run. In lower-resource settings, connectivity and data-residency constraints shape the whole architecture.

Produce: a technical-environment summary with constraints that will affect the build.

### 6. Security review
Assess the current security posture against the environment the assistant will live in: authentication, access control, network exposure, secrets handling, and existing incident capability. This feeds the Part 5 threat model.

Produce: a security-posture summary and a list of gaps to close before go-live.

### 7. Skills assessment
Assess the staff's capability to use and operate the system: technical literacy, change appetite, and who could own operations after handover. A brilliant system nobody can run is a failed engagement.

Produce: a skills assessment and the outline of a training need (feeds the Part 7 training plan).

---

## The discovery output: a single findings document

Roll the seven artifacts into one Discovery Findings document with an executive summary. This is the foundation for Strategy (Part 2). Its most important sentence is usually uncomfortable, for example: "Records are unclassified and the corpus is 40 percent duplicates, so a citizen-facing assistant is premature; Phase 1 must be data classification and an internal assistant."

Telling the client the hard truth in discovery is the most valuable thing you do all engagement.

---

## Discovery rules (memorize)

1. **Evidence over impressions.** Every activity ends in a written artifact.
2. **Classify the data or you cannot govern it.** This is the pivotal public-sector output.
3. **Find the gap** between what leadership wants and what staff need.
4. **Surface the hard truth early.** Premature ambition is cheaper to correct in discovery than after building.
5. **Discovery constrains everything downstream.** Do not build ahead of it.

---

## References

- NIST AI Risk Management Framework (AI RMF 1.0) - the "Map" function frames the context, stakeholder, and data-classification discovery described here: https://www.nist.gov/itl/ai-risk-management-framework

Notes:
- The seven discovery activities and the single-findings-document output are SUTA Labs consulting methodology, not an external standard.
- Data-classification categories (public / internal / restricted) and any legal disclosure or records duties depend on [CLIENT]'s jurisdiction and sector; align them to the applicable law rather than to this template. See the Tier 16 public-sector concept references.

---

Prof. Happy (SUTA Labs)
