# Human-Oversight Plan: [SYSTEM NAME]

**Purpose:** make accountability real by defining exactly how humans review,
override, and stop this AI system. Required for every decision-making system, and
mandatory (human in the loop) for high-risk systems. Supports the human-oversight
and accountability principles (Concepts 12.1) and NIST AI RMF (Manage).

**System:** [SYSTEM NAME] - **Risk class:** [minimal / limited / high]
**Owner (accountable person):** [NAME, ROLE]
**Version:** [VERSION] - **Date:** [DATE]

---

## 1. Oversight posture
Select one and justify it against the risk class:

- [ ] **Human in the loop** - a person approves each consequential action before it
  happens. *(Required for high-risk.)*
- [ ] **Human on the loop** - the system acts; a person monitors and can intervene.
- [ ] **Human in command** - a person sets policy and can shut it down but does not
  touch each action.

Justification: [WHY THIS POSTURE FITS THE RISK]

## 2. Who does what

| Role | Responsibility |
|------|----------------|
| Reviewer | Reviews [WHICH outputs], at [WHAT frequency / trigger] |
| Overrider | Can override a decision via [MECHANISM] |
| Emergency stop | [NAME/ROLE] can disable the system via [MECHANISM] |
| Accountable owner | [NAME, ROLE] - answerable for outcomes |

## 3. Review triggers
When must a human look at an output before it takes effect?
- Always, for [WHICH cases - e.g. any denial, any high-value action]
- When the model confidence is below [THRESHOLD]
- On [OTHER trigger]

## 4. Override mechanism
- How a reviewer overrides a decision, step by step: [ANSWER]
- Where the override is logged: [ANSWER]

## 5. Emergency stop
- How to disable the system quickly (kill switch / feature flag / disable route):
  [ANSWER]
- Who is authorized to trigger it: [ANSWER]
- What happens to in-flight work when it stops: [ANSWER]

## 6. Appeals (for decisions about people)
- How an affected person requests human review of a decision: [ANSWER]
- Who handles the appeal and within what timeframe: [ANSWER]

## 7. Evidence and audit
- Where oversight actions (reviews, overrides, stops) are recorded: [ANSWER]
- How often the oversight plan itself is reviewed: [ANSWER]

Prof. Happy (SUTA Labs)
