# Concepts: Capstone Part 3 - Governance

**Tier 18, Module 18.3** - the accountability layer that must exist before you build.

Governance decides what is allowed, who is accountable, and how you stay controlled and defensible. In a public-sector engagement it is not optional and it is not last - it sets the requirements the technical build must satisfy. This module covers the six governance outputs.

**The rule of governance:** governance is a requirement on the build, not a document produced after it. Write it before Part 4, and let it constrain the architecture.

---

## The six governance outputs

### 1. AI policy
The institution's statement of what AI use is allowed, who approves what, and what controls apply. Adapt your Tier 12 toolkit and Tier 16 public-sector policy: human decides all high-impact citizen outcomes; explainability and appeal-grade logging are required; accessibility and bilingual quality are gates; data-handling follows the classification.

Produce: an approved AI policy scoped to this institution.

### 2. Impact assessment
A structured assessment of the system's potential impact on citizens, staff, and the institution - technical, social, and ethical - following the NIST AI RMF "Map" function, which is defined to identify context, stakeholders, system boundaries, and potential harms (see: https://www.nist.gov/itl/ai-risk-management-framework). It identifies who could be harmed and how, and what mitigations apply. For any high-impact use it is mandatory before go-live.

Produce: a completed impact assessment with identified risks and mitigations.

### 3. Human-oversight design
The concrete design of how humans stay in control: which outputs require review, who the accountable human is, how the review is genuine rather than a rubber-stamp, and how a citizen appeal is handled. This is where the Tier 16 appeals scenario becomes a design, not just a principle.

Produce: a human-oversight design specifying review points, accountable roles, and the appeal path - and the technical requirements it places on the build (appeal-grade logging).

### 4. Vendor assessment
An assessment of the third parties in the system - model providers, hosting, libraries - for security, data handling, residency, and reliability. For public sector, where sensitive data goes and whether it crosses borders is a governance decision, not a technical convenience.

Produce: a vendor assessment with the data-flow decisions (what data reaches which provider, and what never leaves the boundary).

### 5. Incident process
The documented process for when something goes wrong: a wrong answer that caused harm, a data leak, a security incident, a challenged decision. Who is notified, who decides, how the system is paused, how citizens are informed, and how it is remediated and recorded.

Produce: an incident-response process, including the pause/rollback authority.

### 6. AI system inventory
A register of the AI systems in use: what they are, their risk level, their owner, their approval status, and their review date. Governance you cannot see is governance you cannot enforce. This is the artifact a regulator or auditor asks for first.

Produce: an AI system inventory entry for the assistant (extensible to future systems).

---

## The governance output: requirements on the build

Governance is not a shelf document. Extract from it the concrete requirements the Part 4 build must satisfy, for example:

- Appeal-grade logging (from human-oversight design)
- Access control mapped to data classification (from the AI policy)
- Citations on every answer (from explainability)
- Data boundaries - what never reaches an external provider (from vendor assessment)
- A pause/rollback capability (from the incident process)
- Accessibility conformance (from the public-sector gates)

Hand this requirements list to Part 4. The build is not done until it meets every one.

---

## Governance rules (memorize)

1. **Governance precedes and constrains the build.** Write it first.
2. **Human decides all high-impact citizen outcomes.** Design the oversight, do not just assert it.
3. **Impact assessment before go-live** for anything high-impact.
4. **Where sensitive data goes is a governance decision**, not a technical shortcut.
5. **If you cannot see it in the inventory, you cannot govern it.**
6. **Governance produces requirements**, and the build must meet every one.

---

## References

- NIST AI Risk Management Framework (AI RMF 1.0), including the Govern, Map, Measure, and Manage functions: https://www.nist.gov/itl/ai-risk-management-framework
- ISO/IEC 42001:2023, Artificial intelligence - Management system (AI policy, impact assessment, third-party/vendor oversight): https://www.iso.org/standard/42001

Notes:
- The six governance outputs and the "governance produces build requirements" model are SUTA Labs consulting methodology built on top of these frameworks, not a verbatim reproduction of either.
- Data-residency, disclosure, and vendor/cross-border obligations depend on [CLIENT]'s jurisdiction and sector. See the Tier 16 concept references for the underlying legal sources.

---

Prof. Happy (SUTA Labs)
