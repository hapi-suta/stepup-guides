# AI Risk-Classification Matrix

**Purpose:** turn an intake submission into a risk class that decides how much
governance a use case needs. Use it consistently so two similar systems get the
same treatment.

**Aligns to:** NIST AI RMF (Map), ISO/IEC 42001 (planning), and the risk tiers in
Concepts 12.4.

---

## Step 1 - Rate severity of potential harm

How bad is it if the system is wrong or misused?

| Severity | Meaning | Examples |
|----------|---------|----------|
| 1 Low | Minor inconvenience, easily reversed | A poor meeting summary |
| 2 Moderate | Real but recoverable harm | A misrouted support ticket |
| 3 High | Significant harm to a person or the org | A wrong content moderation removal |
| 4 Severe | Serious, hard-to-reverse harm to rights, safety, money | A wrongful benefit denial, an unsafe clinical suggestion |

## Step 2 - Rate scale of exposure

How many people, how often, how autonomously?

| Exposure | Meaning |
|----------|---------|
| 1 Narrow | A few internal users, human checks every output |
| 2 Moderate | A team or single workflow, humans monitor |
| 3 Broad | Many customers/citizens, or the system acts with little human review |

## Step 3 - Combine into a risk class

Find severity (rows) against exposure (columns):

| Severity \ Exposure | 1 Narrow | 2 Moderate | 3 Broad |
|---------------------|----------|------------|---------|
| 1 Low | Minimal | Minimal | Limited |
| 2 Moderate | Minimal | Limited | Limited |
| 3 High | Limited | High | High |
| 4 Severe | High | High | High |

## Step 4 - Apply the override rules

Regardless of the grid above:

- **Unacceptable** (do not proceed) if the use is prohibited by law or by
  [ORGANIZATION] policy (for example manipulative, discriminatory, or
  prohibited-surveillance uses). Reject.
- **High** if the system makes or heavily influences a consequential decision
  about a person (money, health, freedom, employment, access to a service),
  even if the grid says lower. When in doubt, round up.

## What each class requires

| Class | Required governance |
|-------|---------------------|
| Minimal | Register in the AI system inventory. Light monitoring. |
| Limited | Inventory + transparency to users + basic monitoring + named owner. |
| High | Inventory + full impact assessment + human in the loop + appeals path + [LEGAL] review + heightened monitoring + named owner. |
| Unacceptable | Do not build or buy. Document the rejection reason. |

## Worked example (delete before client use)

A citizen-facing benefits-eligibility assistant: severity 4 (severe - denies a
benefit), exposure 3 (broad - all applicants). Grid says High, and the override
(consequential decision about a person) confirms High. It needs a full impact
assessment, human in the loop, and an appeals path.

Prof. Happy (SUTA Labs)
