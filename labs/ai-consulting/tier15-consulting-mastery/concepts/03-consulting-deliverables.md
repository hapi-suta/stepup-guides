# Concepts: Consulting Deliverables

**Tier 15, Module 15.3** - The documents and frameworks an AI consultant produces to turn an engagement into decisions, action, and paid outcomes.

As a consultant, you are not paid for the hours you sit in meetings. You are paid for the artifacts that survive after you leave the room. A deliverable is a written object that a client can read, act on, forward to their boss, and hold you accountable to. Good deliverables make your thinking visible, defensible, and reusable. Bad deliverables are long, vague, and get filed and forgotten. This module defines the fourteen deliverables that make up almost every AI consulting engagement, and for each one it tells you the purpose, the audience, and what "good" actually looks like. Learn to produce these well and you can run a full engagement from first call to signed follow-on work.

A quick map before the detail:

| Deliverable | Primary audience | One-line purpose |
| --- | --- | --- |
| Executive summary | C-suite, sponsor | Give the decision-maker the answer in 60 seconds |
| Current-state assessment | Sponsor, operations leads | Describe the client as they are today, with evidence |
| Readiness score | Sponsor, steering committee | Rate how prepared the client is to adopt AI |
| Use-case inventory | Sponsor, business unit leads | List every candidate AI opportunity found |
| Prioritization matrix | Steering committee | Rank use cases by value versus effort |
| Risk register | Sponsor, legal, security | Name what could go wrong and who owns it |
| Target architecture | Technical leads, IT | Show the future-state system at a high level |
| Governance model | Legal, compliance, sponsor | Define who decides what, and the guardrails |
| Pilot charter | Project team, sponsor | Scope one experiment tightly enough to run it |
| Statement of work | Procurement, sponsor | The contract: scope, price, terms |
| Roadmap | Sponsor, steering committee | Sequence the work over quarters |
| Budget | Finance, sponsor | Estimate the money required and its return |
| Success metrics | Sponsor, business owners | Define how everyone will know if it worked |
| Final presentation | Full leadership audience | Tell the whole story live and win the next step |

---

### Executive summary

**Purpose.** Deliver the entire conclusion of your work in one page, so a busy leader who reads nothing else still knows what you found, what you recommend, and what it costs. It is the deliverable most likely to be read and least likely to be read carefully, so it must front-load the answer.

**Audience.** The economic buyer and the C-suite. These are people with limited time who will decide whether to fund the next phase. They think in outcomes, money, and risk, not in technical detail.

**What good looks like.** One page, maximum two. It opens with the recommendation, not the background. It answers four questions in order: what is the situation, what did we find, what do we recommend, and what is the ask (money, time, decision). It uses plain business language, quantifies wherever possible ("[CLIENT] can cut invoice processing time by an estimated 40 percent"), and never requires the reader to flip to another document to understand it. A good test: if the summary were the only page that survived, the client could still make the go or no-go decision.

A reliable structure:

```
1. Situation      - why we were engaged (1-2 sentences)
2. Findings       - the 2-4 things that matter most
3. Recommendation - the single clear path forward
4. The ask        - budget, timeline, and the decision needed now
```

---

### Current-state assessment

**Purpose.** Establish an honest, evidence-based picture of how the client operates today - their processes, data, technology, skills, and pain points - before you propose any change. It is the baseline that every later recommendation refers back to.

**Audience.** The sponsor and the operational leaders whose work you assessed. They will check it for accuracy, so it must reflect reality, not a sanitized version.

**What good looks like.** Specific and observed, not generic. It names actual systems, actual volumes, and actual bottlenecks ("[CLIENT] processes roughly 12,000 support tickets a month across three disconnected tools"). It separates fact from interpretation. It is fair - it credits what works today, not only what is broken - which builds trust and keeps the client from getting defensive. It cites its sources: interviews conducted, documents reviewed, systems inspected. A weak assessment reads like it could describe any company; a strong one could only describe this one.

---

### Readiness score

**Purpose.** Convert the current-state assessment into a simple rating of how prepared the organization is to adopt AI successfully. It turns a wall of findings into a number leaders can grasp and compare over time.

**Audience.** The sponsor and the steering committee. They use it to set expectations and to decide whether to invest in foundations first or move straight to use cases.

**What good looks like.** Scored across a small set of named dimensions, each with a defined scale and written justification. Common dimensions are data, technology, talent, process maturity, leadership sponsorship, and governance. The score is never a lone number floating in space - it is always backed by the evidence behind each dimension, so the client understands *why* they scored low on data and what raising it would take.

```
Dimension            Score (1-5)   Basis
-------------------  -----------   ------------------------------
Data quality             2         Siloed, no single customer view
Technology platform      3         Cloud-capable, limited MLOps
Talent and skills        2         No in-house ML engineers
Process maturity         3         Documented but manual
Leadership sponsorship   4         Named exec sponsor, funded
Governance               1         No AI policy or review process
-------------------  -----------   ------------------------------
Overall readiness      2.5 / 5     Foundations needed before scale
```

---

### Use-case inventory

**Purpose.** Capture every candidate AI opportunity you identified during discovery, in one place, described consistently, so nothing is lost and everything can be compared. It is the raw material the prioritization matrix will rank.

**Audience.** The sponsor and business unit leaders, who will recognize their own ideas here and want to see them treated seriously.

**What good looks like.** Complete and consistent. Each use case gets the same short template so they can be compared apples-to-apples: name, business problem, proposed AI approach, expected value, data required, and rough effort. It is broad at this stage - you are cataloguing, not judging - so a good inventory captures small quick wins alongside large transformational bets. Every entry is written in business terms first ("reduce time to answer customer emails"), with the AI technique second.

| ID | Use case | Problem it solves | Expected value | Data needed |
| --- | --- | --- | --- | --- |
| UC-01 | Support email triage | Slow first response | -30% response time | Historical tickets |
| UC-02 | Contract clause extraction | Manual legal review | -50% review hours | Signed contracts |
| UC-03 | Demand forecasting | Overstock and stockouts | -15% carrying cost | Sales history |

---

### Prioritization matrix

**Purpose.** Rank the use-case inventory so the client knows what to do first. It replaces "everyone argues for their favorite project" with a shared, visible logic for sequencing.

**Audience.** The steering committee. This is a group decision tool, meant to be projected on a screen and debated.

**What good looks like.** A two-axis grid, almost always business value against effort or feasibility, with each use case plotted as a dot. The top-left quadrant - high value, low effort - is the set of quick wins you lead with. The matrix is transparent about how each use case was scored, so the placement can be defended when someone's pet project lands in the low-value corner. Good prioritization also flags dependencies: a use case that unlocks three others may be worth doing even if its own value is modest.

```
        High value
            |
  Big bets  |  Quick wins   <- start here
 (plan for) |  (do now)
------------+------------ Low effort
  Avoid /   |  Fill-ins
  defer     |  (if capacity)
            |
        Low value
```

---

### Risk register

**Purpose.** Name everything that could go wrong, rate how likely and how damaging each risk is, and assign an owner and a mitigation to each. It shows leadership you have thought past the happy path, and it is a live document the project keeps updating.

**Audience.** The sponsor, plus legal, security, and compliance stakeholders. For AI work this is where regulatory, bias, privacy, and model-failure risks live.

**What good looks like.** Specific and owned. Vague entries like "AI might not work" are useless; good entries read "model may produce biased loan decisions, exposing [COMPANY] to regulatory penalty." Each risk has a likelihood, an impact, a named owner, and a concrete mitigation. It covers the full range - technical, data, ethical, legal, operational, and change-management risk - not just the technical failures. A strong register is prioritized so attention goes to the high-likelihood, high-impact rows first.

| ID | Risk | Likelihood | Impact | Owner | Mitigation |
| --- | --- | --- | --- | --- | --- |
| R-01 | Biased model outputs | Medium | High | Compliance lead | Bias testing + human review |
| R-02 | Training data privacy breach | Low | High | Security lead | Data minimization + access controls |
| R-03 | Low user adoption | High | Medium | Business owner | Change plan + training |

---

### Target architecture

**Purpose.** Show, at a level a non-engineer can follow, what the future-state system will look like - where data comes from, where the AI models live, how they connect to existing tools, and where humans stay in the loop. It aligns the technical team and reassures IT that the plan fits their environment.

**Audience.** Technical leads and IT leadership, with a simplified version for the sponsor. Two versions of this deliverable often exist: a detailed one for engineers and a one-diagram one for executives.

**What good looks like.** A clear diagram plus a short narrative. It shows the major components and the flow of data between them, names key technology choices with the reasoning behind them, and honestly marks what is new versus what reuses existing systems. Good target architecture is pitched at the right altitude for its reader - the executive version has boxes and arrows, not vendor product names and protocols. It also addresses the non-functional realities: security, data residency, cost, and how the system will be operated after go-live.

```
[ Source systems ] --> [ Data pipeline ] --> [ Feature store ]
                                                    |
                                                    v
[ User apps ] <-- [ API layer ] <-- [ Model serving + human review ]
                                                    |
                                          [ Monitoring + governance ]
```

---

### Governance model

**Purpose.** Define who is allowed to decide what, and the guardrails everyone must follow, so AI is adopted responsibly rather than as an uncontrolled free-for-all. It answers "who approves a new model going live" and "what are our rules on data, bias, and transparency."

**Audience.** Legal, compliance, risk, and the executive sponsor. This is the deliverable that keeps the client out of trouble with regulators and their own board.

**What good looks like.** Practical, not a policy no one reads. It names the decision bodies (for example an AI review committee), the roles and their authority, the review gates a use case must pass before launch, and the standing rules for data use, human oversight, monitoring, and incident response. Good governance is proportionate - a two-person startup does not need the same apparatus as a bank - and it maps to a recognized framework such as the NIST AI Risk Management Framework (see: https://www.nist.gov/itl/ai-risk-management-framework) or ISO/IEC 42001 (see: https://www.iso.org/standard/42001) so it is credible and auditable.

```
Roles              Decision rights
---------------    --------------------------------------------
AI review board    Approve/reject new models before production
Model owner        Accountable for one model's performance + risk
Data steward       Approves data sources and usage
Executive sponsor  Funds initiatives, resolves escalations

Review gates: concept -> data-use approval -> pre-launch risk review -> live monitoring
```

---

### Pilot charter

**Purpose.** Scope a single experiment tightly enough that it can actually be run, measured, and judged in a fixed window. It prevents the classic failure where a "pilot" quietly expands until it never finishes.

**Audience.** The project team who will execute, and the sponsor who funds and protects the pilot. It is the shared agreement on what this specific test is and is not.

**What good looks like.** Small, time-boxed, and measurable. It states one clear objective, an explicit scope with named exclusions, the success criteria decided *in advance*, the duration, the resources, and what decision the pilot will inform ("if we hit 80 percent accuracy on 500 real tickets in six weeks, we proceed to phase two"). A good charter names the go/no-go decision and who makes it, so the pilot ends in a decision rather than drifting into permanent limbo.

```
Objective:        Validate email-triage model on live tickets
In scope:         English tickets, top 3 categories
Out of scope:     Non-English, phone, automated replies
Success criteria: >= 80% routing accuracy on 500 tickets
Duration:         6 weeks
Decision at end:  Scale / iterate / stop (owner: [sponsor])
```

---

### Statement of work

**Purpose.** The contract. It defines exactly what you will deliver, for how much, by when, and under what terms, so both sides have a single source of truth and neither is surprised. It is where scope creep is prevented and where you protect yourself as the consultant.

**Audience.** Procurement, legal, and the sponsor. This is a legally significant document read by people looking for gaps and obligations.

**What good looks like.** Precise and unambiguous. It lists concrete deliverables with acceptance criteria, the timeline and milestones, the price and payment schedule, the responsibilities of *both* parties (client access, data, sign-offs), assumptions, and how changes are handled. Good SOWs make the boundaries explicit - what is included and, just as importantly, what is not - because most disputes come from silence, not disagreement. Every deliverable named here should trace back to something in the roadmap and budget.

---

### Roadmap

**Purpose.** Sequence the recommended work across time, usually in quarters, so leadership sees the journey from foundations to first pilot to scaled adoption. It turns a pile of prioritized use cases into a phased plan with a rhythm.

**Audience.** The sponsor and steering committee, who use it to plan funding and set expectations with the rest of the business.

**What good looks like.** Phased, realistic, and dependency-aware. It groups work into logical stages (often: foundation, pilot, scale), shows what happens in each, and puts the enabling work - data, governance, skills - before the use cases that depend on it. A good roadmap has clear milestones and decision points between phases rather than one continuous blur, and it is honest about pace: it does not promise six transformational projects in one quarter.

```
Q1  Foundations   Data cleanup, governance stand-up, team hiring
Q2  Pilot         Run UC-01 pilot, prove value, refine
Q3  Expand        Roll out UC-01, start UC-02
Q4  Scale         Productionize, add monitoring, plan next wave
      ^ go/no-go decision gate between each phase
```

---

### Budget

**Purpose.** Estimate the money the plan requires and, wherever possible, the return it produces, so the sponsor can secure funding and justify it. It converts the roadmap into dollars.

**Audience.** Finance and the economic buyer. These readers scrutinize numbers, so credibility is everything.

**What good looks like.** Broken down, defensible, and paired with expected return. It separates categories - people, technology and licenses, infrastructure, training, ongoing run costs - and it distinguishes one-time build costs from recurring operating costs, which clients often forget. Good budgets show ranges or clearly-stated assumptions rather than false precision, and they place cost next to the expected benefit so the reader sees value, not just spend. Always include ongoing costs; a project that looks cheap to build and expensive to run has sunk many AI initiatives.

| Category | One-time | Annual recurring |
| --- | --- | --- |
| Consulting / build | $180,000 | - |
| Cloud + infrastructure | $20,000 | $60,000 |
| Software licenses | - | $40,000 |
| Training + change | $30,000 | $10,000 |
| **Total** | **$230,000** | **$110,000** |
| Estimated annual benefit | | **$400,000** |

---

### Success metrics

**Purpose.** Define, before work starts, how everyone will know whether the initiative worked. It creates shared accountability and prevents the end-of-project argument over whether it was a success.

**Audience.** The sponsor and the business owners who live with the results. Metrics only matter if the people responsible for them agree to them up front.

**What good looks like.** Tied to business outcomes, measurable, and baselined. Good metrics connect a technical result to a business result - not "model accuracy is 90 percent" alone, but "response time dropped from 8 hours to 2." Each metric has a current baseline, a target, and a defined way to measure it, so improvement is provable. A strong set is small (a handful, not thirty), balanced across value, adoption, and quality, and agreed by the business owner who will be judged on it.

| Metric | Baseline | Target | How measured |
| --- | --- | --- | --- |
| Avg first-response time | 8 hrs | < 2 hrs | Ticketing system report |
| Tickets auto-routed correctly | 0% | >= 80% | Weekly audit sample |
| Agent adoption of tool | - | >= 70% | Usage logs |

---

### Final presentation

**Purpose.** Tell the whole story live, in one session, to the assembled leadership - and secure the decision to proceed. Every other deliverable feeds this one. It is where the engagement is won or lost, because decisions get made in the room, not in the appendix.

**Audience.** The full leadership audience: the sponsor, the C-suite, and often skeptics you have not met. Mixed technical fluency, short attention, high stakes.

**What good looks like.** A narrative, not a data dump. It follows a clear arc: here is where you are, here is what we found, here is what we recommend, here is what it takes, here is the decision we need today. It leads with the answer, uses the strong visuals from your other deliverables (the matrix, the roadmap, the readiness score), and keeps the detail in a backup appendix rather than on the main slides. Good final presentations rehearse for the hard questions, name the risks honestly before someone else does, and end with a single, concrete call to action. The measure of success is simple: the client says yes to the next step.

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can do all three:

1. Name all fourteen deliverables from memory and, for any one drawn at random, state its purpose, its primary audience, and one concrete marker of what "good" looks like.
2. Explain how the deliverables connect - specifically, trace how the current-state assessment feeds the readiness score, how the use-case inventory feeds the prioritization matrix, and how the roadmap, budget, and statement of work must agree with one another.
3. Given a short client scenario, draft a credible one-page executive summary and a five-row prioritization matrix using the structures in this document, in business language with no unexplained jargon.

## References

- [NIST AI Risk Management Framework (AI RMF 1.0)](https://www.nist.gov/itl/ai-risk-management-framework) - the framework the governance-model deliverable maps to.
- [ISO/IEC 42001:2023 - Information technology - Artificial intelligence - Management system](https://www.iso.org/standard/42001) - the auditable AI management-system standard for the governance model.
- [McKinsey - The state of AI: how organizations are rewiring to capture value](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-state-of-ai-how-organizations-are-rewiring-to-capture-value) - why roadmaps, KPIs, and defined ownership drive realized value.
- [Harvard Business Review - Building the AI-Powered Organization (2019)](https://hbr.org/2019/07/building-the-ai-powered-organization) - scaling AI beyond pilots depends on the organizational structures these deliverables define.
