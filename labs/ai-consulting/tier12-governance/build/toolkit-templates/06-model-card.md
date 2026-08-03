# Model Card: [MODEL / SYSTEM NAME]

**Purpose:** the "label on the box" for a model or AI system - what it is for, what
it is not for, how it performs, and where it fails. Supports transparency
(Concepts 12.1) and is evidence for NIST AI RMF (Map/Measure) and ISO/IEC 42001.

**Version:** [VERSION] - **Date:** [DATE] - **Owner:** [NAME, ROLE]

> One model card per model version. Update it when the model or its evaluation
> changes. Written so a non-specialist manager can understand it.

---

## 1. Overview
- Model / system name: [NAME]
- What it does, in plain language: [ANSWER]
- Model type / base model / provider: [e.g. Claude via Bedrock, or a custom
  scikit-learn classifier]
- Version and date: [ANSWER]

## 2. Intended use
- Intended tasks: [ANSWER]
- Intended users: [ANSWER]
- Intended context / deployment: [ANSWER]

## 3. Out-of-scope use
Uses this model should NOT be put to (and why):
- [OUT-OF-SCOPE USE 1]
- [OUT-OF-SCOPE USE 2]

## 4. Training / configuration data
- For custom models: what data trained it, from when, how collected. [ANSWER]
- For third-party models: what the vendor discloses about training data. [ANSWER]
- Link to the data sheet: [LINK]

## 5. Evaluation
- Metrics used and why (not just accuracy): [e.g. precision, recall, F1,
  groundedness, disparate-impact ratio]
- Results on a held-out / golden set: [NUMBERS]
- Baseline it beats: [BASELINE + NUMBER]
- Date of last evaluation: [DATE]

## 6. Fairness considerations
- Groups considered: [ANSWER]
- Fairness metric + result: [e.g. disparate-impact ratio = 0.49, FLAGGED]
- Known proxy-variable risks: [ANSWER]
- Mitigations applied: [ANSWER]

## 7. Limitations and known failure modes
- [LIMITATION 1 - e.g. degrades on inputs outside the training distribution]
- [LIMITATION 2 - e.g. can hallucinate when the retrieval context is empty]
- [LIMITATION 3]

## 8. Human oversight
- Oversight posture and owner: [in the loop / on the loop / in command; NAME]
- Link to the human-oversight plan: [LINK]

## 9. Ethical and safety notes
- Potential harms and how they are mitigated: [ANSWER]
- Link to the impact assessment: [LINK]

## 10. Maintenance
- Who maintains this card and how often it is reviewed: [ANSWER]

Prof. Happy (SUTA Labs)
