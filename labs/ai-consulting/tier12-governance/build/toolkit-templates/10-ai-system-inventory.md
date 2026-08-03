# AI System Inventory

**Purpose:** the living register of every AI system [ORGANIZATION] runs. You cannot
govern what you have not inventoried, and unknown "shadow AI" is a top risk. This
is the backbone of NIST AI RMF (Govern) and ISO/IEC 42001 (organizational context
and operational controls).

**Owner:** [POLICY OWNER ROLE] - **Last updated:** [DATE] - **Review cadence:**
[e.g. quarterly]

> Every AI system - built or bought - gets a row. No exceptions. Keep it current:
> add on approval, update on change, mark retired on decommission.

---

## Inventory

| ID | System name | Purpose | Owner (role) | Vendor / in-house | Risk class | Status | Last impact assessment | Last review | Notes |
|----|-------------|---------|--------------|-------------------|-----------|--------|------------------------|-------------|-------|
| AI-001 | [NAME] | [PURPOSE] | [ROLE] | [VENDOR/in-house] | [minimal/limited/high] | [pilot/production/retired] | [DATE] | [DATE] | [NOTES] |
| AI-002 | | | | | | | | | |
| AI-003 | | | | | | | | | |

## Field definitions

- **ID:** stable identifier (AI-001, AI-002, ...).
- **Purpose:** what business job it does, one line.
- **Owner (role):** the accountable person/role - never blank, never "the vendor".
- **Vendor / in-house:** who provides the model/system.
- **Risk class:** from the risk-classification matrix.
- **Status:** pilot, production, or retired.
- **Last impact assessment:** date of the most recent completed assessment (blank
  is a governance gap for anything above minimal).
- **Last review:** date the entry was last verified as accurate.
- **Notes:** links to model card, oversight plan, open incidents.

## Health check (run when reviewing the inventory)

- Every production system above "minimal" has a dated impact assessment. [Y/N]
- Every system has a named owner. [Y/N]
- No production system has a "Last review" older than [CADENCE]. [Y/N]
- No high-risk system lacks a human-oversight plan. [Y/N]

Any "N" is a finding for the executive dashboard.

Prof. Happy (SUTA Labs)
