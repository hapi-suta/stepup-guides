# Concepts: Consulting Discovery

**Tier 15, Module 15.1** - Discovery is the structured investigation you run before you propose any AI solution, so your recommendation fits the client's real business, not the one you imagined.

Discovery is where a consultant earns trust and avoids the biggest failure in AI consulting: recommending a solution that solves the wrong problem. Before you can help [CLIENT], you have to understand how the business actually runs, who does what, where the pain is, what the data looks like, and what the organization can realistically absorb. A good discovery keeps you from over-promising, protects your reputation, and produces the raw material for every deliverable that follows (the current-state map, the opportunity list, the roadmap, and the proposal). Weak discovery is why so many AI projects stall after the pilot: the consultant never saw the constraint that would kill it.

This concept walks through nine discovery activities. Treat them as a toolkit, not a checklist you run in strict order. On a small engagement you might do three of them in a week. On an enterprise transformation you might spend a month on all nine.

---

## The shape of a discovery

Discovery moves from the outside in: from what leaders believe, to what actually happens on the ground, to what the systems and data can prove. Each layer tests the one before it. Executives tell you the strategy; department interviews tell you whether the strategy survives contact with the work; observation tells you whether the interviews were honest; documents and data tell you whether any of it is true.

```
        EXECUTIVES        -> strategy, priorities, money, mandate
            |
        DEPARTMENTS       -> real workflows, pain, workarounds
            |
        OBSERVATION       -> what people actually do (vs. what they say)
            |
   DOCUMENTS + DATA       -> the ground truth the org runs on
            |
   TECH / RISK / SKILLS   -> can we build it, is it safe, can they run it
            |
        VENDORS           -> build vs. buy reality check
            |
            v
   CURRENT-STATE MAP + OPPORTUNITY LIST
```

| Discovery activity | Answers the question | Primary output |
|---|---|---|
| Executive interviews | Why are we doing this, and what does success mean? | Objectives and success criteria |
| Department interviews | How does the work really happen? | Workflow narratives, pain points |
| Workflow observation | What do people actually do, step by step? | Verified process maps, time data |
| Document review | What rules and artifacts govern the work? | Process/policy inventory |
| Data discovery | What data exists, and is it usable? | Data inventory and readiness rating |
| Technical assessment | What can the tech environment support? | Architecture and constraints memo |
| Risk assessment | What could go wrong, legally or operationally? | Risk register |
| Skills assessment | Can the team build, use, and sustain this? | Capability gap analysis |
| Vendor review | Should we build or buy, and from whom? | Vendor landscape and shortlist |

---

### Executive interviews

**Purpose.** Establish why the engagement exists, what leadership counts as success, how much appetite and budget there is, and who has the authority to make decisions and unblock you. Everything downstream is measured against what you learn here.

**Who and what it involves.** One-on-one conversations, 45 to 60 minutes each, with the sponsor and other senior leaders (CEO, COO, CFO, business-unit heads, sometimes the CIO or CDO). One-on-one, not group, so you get candor. Recorded or carefully noted. This is the only layer where you are talking to people who control money and mandate, so treat their time accordingly.

**Key questions to ask.**
- What business outcome are you trying to change, and by how much?
- How will you know in twelve months that this was worth doing?
- What has already been tried, and why did it stall?
- What is the budget range and who signs off?
- What is off-limits (systems we cannot touch, teams we cannot disrupt)?
- Who else must be bought in for this to succeed?

**Outputs.** A short objectives-and-success-criteria document, named decision-makers and sponsors, budget and timeline boundaries, and a list of stated constraints. This becomes the yardstick for scoring every opportunity you find later.

---

### Department interviews

**Purpose.** Understand how work actually flows through each function, where the friction and delays live, and where staff have built workarounds. Executives describe the strategy; departments describe the reality that strategy has to work inside.

**Who and what it involves.** Interviews with managers and frontline staff in the functions in scope (for example [COMPANY]'s finance, operations, customer support, and sales teams). Mix managers and doers - managers know the intent, doers know the exceptions. Groups of two to four can work here, but watch for people softening the truth in front of a boss.

**Key questions to ask.**
- Walk me through a typical [task] from start to finish.
- Where does this slow down or get stuck?
- What do you do when the normal process breaks?
- Which parts are repetitive or boring enough that you wish they were automated?
- What would you fix first if you could?

**Outputs.** Written workflow narratives per department, a running list of pain points with rough frequency and impact, and candidate automation opportunities. These are hypotheses at this stage - observation and data will confirm or kill them.

---

### Workflow observation

**Purpose.** See what people actually do, which is often different from what they told you in interviews. People forget steps, skip the annoying parts when describing their day, and underreport the manual fixes they do on autopilot. Observation catches the gap between the described process and the real one.

**Who and what it involves.** Sitting with staff while they work (in person or over a screen share), timing tasks, counting steps, and noting every place a human copies, re-keys, checks, or waits. No interrupting mid-task; ask questions after. This is where you find the swivel-chair work (moving data between systems by hand) that is invisible in every diagram the client will show you.

**Key questions to ask (after observing).**
- You did a step there that was not in the description - what was that?
- How often does that exception happen?
- What happens if you skip that check?
- How long did that actually take, start to finish?

**Outputs.** Verified, step-level process maps, real cycle-time and volume data (how long, how often), and a tally of manual touchpoints. This is your strongest evidence for where AI or automation genuinely saves time.

---

### Document review

**Purpose.** Capture the rules, artifacts, and prior work that govern how the business operates: policies, standard operating procedures, contracts, org charts, past project post-mortems, and reports. Documents reveal the official version of the truth, which you compare against what people actually do.

**Who and what it involves.** You request and read the client's existing materials: SOPs, compliance and policy documents, sample outputs (reports, invoices, tickets), org charts, prior consulting decks, and any earlier AI or automation attempts. Ask for real examples, not idealized templates - the messy real invoice tells you more than the clean sample.

**Key questions to ask (of the documents and their owners).**
- Is this document current, and who owns it?
- Do people actually follow this, or is it aspirational?
- What prior projects touched this area, and what happened to them?
- Which policies constrain what we are allowed to automate?

**Outputs.** An inventory of processes and governing policies, a list of relevant constraints (regulatory, contractual, internal), and lessons from prior attempts so you do not repeat a known failure.

---

### Data discovery

**Purpose.** Find out what data the organization has, where it lives, and whether it is good enough to build AI on. AI is only as good as the data behind it, so this activity often decides whether an opportunity is real or a fantasy.

**Who and what it involves.** Working with data owners, analysts, and IT to catalog data sources (databases, spreadsheets, SaaS exports, documents), understand their volume, freshness, quality, and access rules. You are assessing readiness, not moving data. Rate each source on completeness, accuracy, consistency, and how easily you can get to it.

**Key questions to ask.**
- What data do we have that describes this process, and where is it?
- How complete and how clean is it? How many gaps and duplicates?
- How current is it - real time, daily, or a stale export?
- Who owns access, and what are the privacy or compliance rules on it?
- Has anyone tried to use this data before, and how did that go?

**Outputs.** A data inventory (source, owner, volume, quality, access), a readiness rating per source, and a list of data gaps that must be closed before a given opportunity is feasible.

```
DATA READINESS (per source)
  Completeness  [####------] does it cover the whole process?
  Accuracy      [#####-----] can we trust the values?
  Consistency   [######----] same format, same meaning everywhere?
  Accessibility [###-------] can we actually get to it, legally + technically?
  -> Overall: NOT READY / NEEDS WORK / READY
```

---

### Technical assessment

**Purpose.** Understand the environment any solution will live in: existing systems, integration points, cloud footprint, security posture, and hard constraints. This tells you what is buildable and where the landmines are before you design anything.

**Who and what it involves.** Conversations and reviews with IT, engineering, and security leaders. You are mapping the system landscape (core applications, databases, APIs, identity, hosting), not doing a code audit. Note where things connect, where they do not, and what rules govern change (release cycles, approval gates, data residency).

**Key questions to ask.**
- What are the core systems, and how do they connect (APIs, files, manual)?
- Where does the data live - on-prem, which cloud, or mixed?
- What are the security and access rules for adding a new system?
- What can we integrate with easily, and what is effectively locked?
- Who has to approve a technical change, and how long does that take?

**Outputs.** A current-state architecture summary, a list of integration options and blockers, and a technical constraints memo that will shape the feasibility of each opportunity.

---

### Risk assessment

**Purpose.** Identify what could go wrong before it does: legal, regulatory, ethical, operational, and reputational risks. For AI specifically this means bias, privacy, explainability, security, and over-reliance on a model. Naming risks early is what separates a trusted advisor from a vendor.

**Who and what it involves.** Working with legal, compliance, security, and business owners to surface risks tied to the proposed direction, then rating each by likelihood and impact and noting a mitigation. Use a recognized frame (for example, the NIST AI Risk Management Framework's four functions: Govern, Map, Measure, and Manage) so nothing obvious is missed. (see: https://www.nist.gov/itl/ai-risk-management-framework)

**Key questions to ask.**
- What is the worst outcome if the AI is wrong, and who is harmed?
- What regulations apply (privacy, sector rules, AI-specific law)?
- Could this system produce biased or unexplainable decisions?
- What data leaves our control, and where does it go?
- What happens if the vendor or model disappears?

**Outputs.** A risk register (risk, likelihood, impact, owner, mitigation), a short list of red-line risks that could block the project, and compliance requirements to build into the design.

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Model produces biased outputs | Medium | High | Bias testing + human review gate |
| PII exposed to third-party model | Medium | High | Data masking, contractual controls |
| Staff over-trust the AI | High | Medium | Confidence display + audit sampling |
| Regulation shifts mid-project | Low | High | Track policy, keep design modular |

---

### Skills assessment

**Purpose.** Determine whether the organization can build, adopt, and sustain the solution after you leave. A brilliant recommendation the client cannot operate is a failed engagement. This activity finds the gap between what the solution needs and what the people can do.

**Who and what it involves.** Reviewing team composition, roles, and capabilities with HR and department leads: technical skills (data, engineering, ML), operational skills (running and monitoring the tool), and change-readiness (willingness to adopt). Compare required skills against present skills and mark each gap as hire, train, or partner.

**Key questions to ask.**
- Who will run and maintain this once we are gone?
- Does the team have the data and technical skills the solution needs?
- How has this group handled past technology changes?
- What is the appetite for learning new tools?
- Where will we hire, where will we train, and where will we bring in a partner?

**Outputs.** A capability gap analysis (skill needed vs. skill present vs. plan to close), a training-and-hiring recommendation, and a change-readiness read that flags adoption risk.

---

### Vendor review

**Purpose.** Decide build versus buy, and if buying, understand the market of tools and partners so your recommendation is grounded rather than guessed. Clients pay you partly to know the landscape they do not have time to research.

**Who and what it involves.** Scanning the vendor and platform market relevant to the opportunity (AI platforms, point solutions, systems integrators, cloud providers), then scoring candidates on fit, cost, maturity, security, support, and lock-in. Include the client's incumbent vendors - the cheapest path is often extending something they already own.

**Key questions to ask.**
- Are there proven tools that already solve this, or must we build?
- How mature is each vendor, and who else uses them at our scale?
- What is the total cost - licensing, integration, and ongoing?
- How much lock-in are we accepting, and how hard is exit?
- How do they handle security, data, and support?

**Outputs.** A vendor landscape summary, a scored shortlist against clear criteria, and a build-versus-buy recommendation with reasoning.

---

## How the pieces fit together

No single activity gives you the answer. Confidence comes from triangulation: when the executive's stated priority, the department's described pain, the observed reality, and the data all point the same way, you have a real opportunity. When they conflict - the CEO wants automation the data cannot support, or a team asks for a tool their skills cannot sustain - discovery has done its job by catching it before the proposal.

The combined output of all nine activities is two deliverables that drive the rest of the engagement: a **current-state map** (how [CLIENT] works today, with evidence) and a **prioritized opportunity list** (where AI can help, scored on value, feasibility, data readiness, risk, and skills). Everything in later modules - the roadmap, the business case, the proposal - is built from these.

---

## Check yourself (Exit gate for this concept)

You are ready to move on when you can:

1. Name all nine discovery activities and, for any one, state its purpose, who it involves, two key questions, and its output without looking.
2. Explain why observation and data discovery can override what you were told in interviews, and give a concrete example of a conflict you would expect to find.
3. Trace how the outputs of discovery feed the current-state map and the prioritized opportunity list, and describe one opportunity that discovery would correctly kill.

---

## References

- [NIST AI Risk Management Framework (AI RMF 1.0)](https://www.nist.gov/itl/ai-risk-management-framework) - the Govern/Map/Measure/Manage functions used in the risk assessment section.
- [ISO/IEC 42001:2023 - Information technology - Artificial intelligence - Management system](https://www.iso.org/standard/42001) - governance and organizational requirements relevant to risk and skills discovery.
- [McKinsey - The state of AI: how organizations are rewiring to capture value](https://www.mckinsey.com/capabilities/quantumblack/our-insights/the-state-of-ai-how-organizations-are-rewiring-to-capture-value) - adoption patterns and where AI value and failure concentrate.
- [MIT Sloan Management Review - Why So Many Data Science Projects Fail to Deliver](https://sloanreview.mit.edu/article/why-so-many-data-science-projects-fail-to-deliver/) - evidence that misalignment with the real business, not the model, is what sinks projects; the case for grounded discovery.
