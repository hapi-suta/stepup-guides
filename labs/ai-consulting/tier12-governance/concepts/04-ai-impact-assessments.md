# Concepts 12.4: AI Impact Assessments

**Tier 12 - Responsible AI and governance.** Teaching reference. An AI impact assessment is the single most important governance artifact you will produce, because it is the one that decides whether a system should exist and how tightly it must be controlled. NIST AI RMF calls for it in the Map function; ISO/IEC 42001 explicitly requires an AI system impact assessment in its planning clause - specifically clause **6.1.4** (see: https://www.iso.org/standard/42001), a requirement it makes over and above the AI risk assessment at 6.1.2. This module is theory only. You will build the template in the toolkit and fill it in for real in USE.

**Who this is for:** consultants who must judge harm before it happens. This is the discipline that separates responsible AI from wishful AI.

**Why it matters:** anyone can list benefits. The consultant is the person in the room who systematically asks "who could this hurt, and what happens when it is wrong?" A completed impact assessment is often the difference between a pilot that gets approved and one that gets stopped by legal - and you want to be the reason it was safe to approve.

---

## 1. What an impact assessment is

An **AI impact assessment** is a structured, written analysis of how an AI system could affect people and the organization - the benefits, the harms, who bears them, and what controls reduce them - produced before deployment and revisited over time. It is not a security review (that is threat modeling, Tier 11) and it is not a performance test (that is evaluation, Tier 10). It is broader: it covers rights, fairness, oversight, and human consequences.

Think of it as a pre-mortem with a paper trail. It forces the uncomfortable questions early, when they are cheap to fix.

---

## 2. The sections your assessment must cover

These are the fields from your spec. Each becomes a section in the template.

### Affected people
Who is touched by this system - directly (the applicant whose loan it scores) and indirectly (the family, the community, the staff whose jobs change)? Name them specifically. "Users" is not an answer; "citizens applying for a housing benefit, and the caseworkers who process appeals" is.

### Intended benefits
What good is this supposed to do, in concrete terms? Faster service, lower cost, better consistency. State it so it can later be measured against reality.

### Possible harms
The core of the assessment. Think across categories: wrong decisions, unfair decisions, privacy loss, safety, erosion of trust, deskilling, and harms from the system being unavailable. Be specific and honest. If you cannot think of a harm, you have not thought hard enough.

### Data sources
Where does the data come from, who owns it, is it accurate, is it representative, and does using it for this purpose have a lawful basis and consent? Bad or unrepresentative data is a direct cause of harm.

### Bias
Could the system disadvantage a protected group? What groups are relevant here? How will bias be measured (selection rate by group, disparate-impact ratio) and what threshold triggers action? Remember proxy variables - dropping the protected attribute does not remove bias.

### Human oversight
What is the oversight posture (in the loop / on the loop / in command, from Concepts 12.1)? Who reviews, who can override, who can stop it? High potential harm demands human in the loop.

### Security
What are the top security risks (link to the Tier 11 threat model) and are the controls in place? An insecure high-impact system is not safe.

### Privacy
What personal or confidential data is involved, how is it protected, minimized, retained, and deleted? Does the vendor train on it?

### Complaints and appeals
When the system is wrong about someone, how does that person find out, complain, and get it reviewed by a human? For high-impact decisions (benefits, credit, employment) an appeals path is often a legal and ethical requirement, not optional.

### Monitoring
After launch, what is watched (accuracy, fairness, drift, safety violations, complaints) and how often? An assessment that is never revisited is a snapshot of a system that has since changed.

### Decommissioning
How does this system get retired safely? What happens to the data, the model, the users depending on it? Systems that cannot be turned off cleanly become permanent liabilities.

---

## 3. Risk classification: deciding how much control

Not every AI system needs the same rigor. The assessment feeds a **risk classification** (you will build the matrix in the toolkit). A common, defensible scheme:

- **Minimal / low risk:** internal productivity tools, low consequence of error, easy human override (a meeting-notes summarizer). Light-touch governance.
- **Limited risk:** customer-facing but low stakes, requires transparency (a support chatbot). Disclosure and basic monitoring.
- **High risk:** affects rights, safety, money, or opportunity - credit, hiring, benefits, healthcare, law enforcement. Full impact assessment, human in the loop, appeals, close monitoring, sometimes legal sign-off.
- **Unacceptable:** uses that are prohibited by law or organizational policy (for example, certain social-scoring or manipulative uses). You say no.

These four labels deliberately mirror the **EU AI Act's** four risk tiers - unacceptable (prohibited), high, limited (transparency obligations), and minimal risk (see: https://artificialintelligenceact.eu/). Using the same vocabulary means your classification lines up with the regulation a European or EU-facing client is measured against. (Your own internal scheme does not have to match the Act's legal definitions exactly - but naming the tiers the same way is a deliberate, defensible choice.)

The classification is driven by two dimensions: **severity of potential harm** and **likelihood / scale of exposure**. High severity plus wide exposure equals high risk, and high risk equals heavy controls.

A quick heuristic to flag high-risk: does the system make or heavily influence a **consequential decision about a person** (their money, health, freedom, employment, or access to a service)? If yes, treat it as high-risk until proven otherwise.

---

## 4. When to run and re-run it

- **Before build:** a lightweight assessment during use-case intake, to decide go / no-go and risk class.
- **Before deployment:** the full assessment, with controls confirmed in place.
- **On material change:** new data source, new model version, new use, or an incident.
- **On a schedule:** periodic review for high-risk systems (for example every 6 or 12 months).

The impact assessment is a living document, versioned like code. A signed, dated version is the evidence an auditor and a regulator will ask for.

---

## Key takeaways

- An AI impact assessment is a structured written analysis of benefits, harms, affected people, and controls, produced before deployment and revisited over time. NIST (Map) and ISO/IEC 42001 both require it.
- Cover every section: affected people, intended benefits, possible harms, data sources, bias, human oversight, security, privacy, complaints/appeals, monitoring, decommissioning.
- The assessment feeds a risk classification (minimal / limited / high / unacceptable) driven by severity of harm and scale of exposure.
- High-risk heuristic: does it make or heavily influence a consequential decision about a person? If yes, treat as high-risk (full controls, human in the loop, appeals) until proven otherwise.
- It is a living, versioned, signed document - the primary evidence for auditors and regulators.

---

## References

- NIST AI RMF 1.0 - Map function (where impact assessment lives) - https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.100-1.pdf
- ISO/IEC 42001:2023 - AI system impact assessment (clause 6.1.4) - https://www.iso.org/standard/42001
- EU AI Act - risk tiers (unacceptable / high / limited / minimal) - https://artificialintelligenceact.eu/

Prof. Happy (SUTA Labs)
