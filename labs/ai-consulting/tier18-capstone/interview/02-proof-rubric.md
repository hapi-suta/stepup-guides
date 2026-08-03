# Capstone Proof-of-Competence Rubric

**Tier 18.** This is how the entire capstone is graded. The capstone is your flagship: it proves every tier was real. A reviewer scores each part, then applies the three final gates. All three gates must pass for the capstone to be complete.

Score each item: **2** = fully met, **1** = partial, **0** = missing. A part passes at 80 percent of its available points, and no single item at 0 on a critical row (marked *).

---

## Part 1 - Discovery
| Item | Score (0-2) |
|---|---|
| Stakeholder interviews produced a real findings log | |
| Process map reflects the actual current workflow | |
| Document inventory is concrete (counts, formats, languages) | |
| * Data classification done (or a classification plan exists) | |
| Technical + security reviews surface real constraints | |
| Skills assessment feeds the training plan | |
| Discovery Findings states the hard truth, not just good news | |

## Part 2 - Strategy
| Item | Score (0-2) |
|---|---|
| Readiness score is honest and evidence-based | |
| Use-case prioritization starts administrative/internal | |
| Business case is honest about costs, including unglamorous ones | |
| Risk classification maps to required controls | |
| * Pilot charter is specific and signed | |
| Success metrics defined before build, measured per language | |
| Every recommendation traces to a discovery finding | |

## Part 3 - Governance
| Item | Score (0-2) |
|---|---|
| AI policy scoped to the institution and approved | |
| Impact assessment identifies real risks + mitigations | |
| * Human-oversight design specifies review points and appeal path | |
| Vendor assessment makes explicit data-boundary decisions | |
| Incident process includes a pause/rollback authority | |
| AI system inventory entry exists | |
| Governance produced a concrete requirements list for the build | |

## Part 4 - Build
| Item | Score (0-2) |
|---|---|
| Bilingual RAG assistant runs with citations | |
| PostgreSQL + pgvector store | |
| Provider abstraction (swap without app changes) | |
| * Access control enforced in SQL, mapped to classification | |
| Appeal-grade audit_log written per response | |
| * Data-boundary enforcement in the provider layer | |
| Pause/rollback endpoint works | |
| Per-language evaluation | |
| Containerized and cloud-deployed | |
| Every Part-3 governance requirement met | |

## Part 5 - Secure
| Item | Score (0-2) |
|---|---|
| Threat model maps every applicable OWASP LLM risk to a test/control | |
| * Prompt-injection validate.sh PASSES | |
| * Role-bypass validate.sh PASSES | |
| * Malicious-document validate.sh PASSES | |
| * Data-leakage validate.sh PASSES | |
| Tool-permission review enforces least agency | |
| Remediation report: findings, fixes, and re-test evidence | |

## Part 6 - Operate
| Item | Score (0-2) |
|---|---|
| CI/CD runs tests + security checks and can roll back | |
| * Backup procedure exists and has been tested | |
| * Recovery procedure exists and has been tested | |
| Monitoring + alerts reach an accountable owner | |
| Model-change process enforces re-eval + re-security-test | |
| Knowledge-base maintenance with provenance + approval | |
| Support workflow with clear routing | |
| Cost controls with a budget ceiling and alert | |

## Part 7 - Present
| Item | Score (0-2) |
|---|---|
| Executive proposal is clear and jargon-free | |
| Architecture diagram is executive-legible | |
| Financial model is honest with stated assumptions | |
| 90-day / 1-year / 3-year roadmaps are concrete | |
| Board deck built to be defended (with demo backup) | |
| Staff-training plan enables eventual independence | |
| Final evaluation report is honest about results and limits | |
| * Board Q&A rehearsed and survived in front of a reviewer | |

---

## The three final gates (all must pass)

1. **Complete package.** All seven parts delivered as a single, coherent, client-ready package - not seven disconnected artifacts.
2. **Security proven.** The RAG assistant passes its full security SURVIVE suite (all four validate.sh scripts return PASS, plus the two review-assessed security scenarios pass review).
3. **Defended live.** The board deck survives a live Q&A rehearsal in front of a real reviewer, with every claim grounded in a deliverable or test result.

---

## The overarching standard

A reviewer reading the whole package should conclude: "This person could actually run this engagement for a real public institution, safely, and defend it to a board." That judgment - not the point total - is the true exit standard. The capstone is your flagship case study; hold it to the standard you would want a client to see.

---

Prof. Happy (SUTA Labs)
