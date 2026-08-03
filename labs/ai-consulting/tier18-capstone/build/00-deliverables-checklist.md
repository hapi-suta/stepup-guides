# Capstone Deliverables Checklist

**Tier 18.** This is the master tracker for the entire capstone. All seven parts must be complete, and the package must be a single client-ready whole. Copy this into your capstone folder and check items off as you finish them. Placeholders: `[CLIENT]`, `[COMPANY]`, `[INDUSTRY]`.

**Capstone:** Secure Responsible AI Adoption Program for a Public-Sector Organization.

---

## Part 1 - Discovery (Concepts)
- [ ] Stakeholder interview log (sponsor, staff, IT/security, legal, citizen rep)
- [ ] Current-state process map + "where AI helps" version
- [ ] Document inventory (count, format, language, owner, freshness, location)
- [ ] Data classification (public / internal / restricted) or a plan to classify
- [ ] Technical-environment review with constraints
- [ ] Security-posture review with gaps
- [ ] Skills assessment
- [ ] Discovery Findings document (rolls up the above, with the hard truth stated)

## Part 2 - Strategy (Concepts)
- [ ] AI readiness score with verdict and top gaps
- [ ] Use-case prioritization with chosen first use case
- [ ] Business case (costs, benefits, break-even)
- [ ] Risk classification with required controls
- [ ] Signed pilot charter
- [ ] Success-metrics table (baseline, target, measurement, per language)
- [ ] Strategy document (decision-ready)

## Part 3 - Governance (Concepts)
- [ ] AI policy (approved, scoped to the institution)
- [ ] Impact assessment (risks + mitigations)
- [ ] Human-oversight design (review points, accountable roles, appeal path)
- [ ] Vendor assessment (data-flow decisions, boundaries)
- [ ] Incident process (with pause/rollback authority)
- [ ] AI system inventory entry
- [ ] Governance requirements list handed to the build

## Part 4 - Build (BUILD)
- [ ] Secure bilingual RAG assistant running
- [ ] PostgreSQL + pgvector store
- [ ] Model-provider abstraction (swap providers without app changes)
- [ ] Authentication
- [ ] Permissions mapped to data classification
- [ ] Citations on every answer
- [ ] Appeal-grade logging
- [ ] Evaluation harness (per language)
- [ ] Monitoring
- [ ] Containerized (Dockerfile)
- [ ] Cloud deployment
- [ ] Every governance requirement met (cross-check the Part 3 list)

## Part 5 - Secure (SURVIVE)
- [ ] Threat model
- [ ] Prompt-injection testing + result
- [ ] Role-bypass testing + result
- [ ] Malicious-document testing + result
- [ ] Data-leakage testing + result
- [ ] Tool-permission review
- [ ] Remediation report (findings + fixes + re-test)
- [ ] Full security SURVIVE suite PASSES

## Part 6 - Operate (USE)
- [ ] CI/CD pipeline
- [ ] Backup procedure (tested)
- [ ] Recovery procedure (tested)
- [ ] Monitoring + alerting live
- [ ] Model-change process (with change control)
- [ ] Knowledge-base maintenance procedure
- [ ] Support workflow
- [ ] Cost controls

## Part 7 - Present (Interview / Executive delivery)
- [ ] Executive proposal
- [ ] Architecture diagram (executive-legible)
- [ ] Financial model
- [ ] 90-day roadmap
- [ ] 1-year roadmap
- [ ] 3-year roadmap
- [ ] Board presentation deck
- [ ] Staff-training plan
- [ ] Final evaluation report
- [ ] Board Q&A rehearsed and survived in front of a reviewer

## Final gates (proof of competence)
- [ ] All seven parts delivered as a single client-ready package
- [ ] RAG assistant passes the full security SURVIVE suite
- [ ] Board deck survives a live Q&A rehearsal with a real reviewer
- [ ] Package graded against the proof-of-competence rubric

---

Prof. Happy (SUTA Labs)
