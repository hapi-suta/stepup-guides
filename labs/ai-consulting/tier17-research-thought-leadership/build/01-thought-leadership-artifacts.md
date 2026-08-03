# BUILD: The Thought-Leadership Artifact Set

**Tier 17 - BUILD phase.** This is the worked structure for producing every artifact type in the Tier 17 publication program. It is not a coding project; it is a production system for durable, defensible work.

**What you produce (the artifact types):** technical articles, AI-governance explainers, research summaries, architecture diagrams, case studies, policy briefs, conference presentations, short educational videos, open-source tools, and templates.

**The end-of-path target (the USE phase tracks this):** 12 strong technical articles, 4 executive AI briefs, 3 published case studies, 2 conference presentations, 1 peer-reviewed or doctoral publication, 1 open-source AI governance toolkit, 1 major public-sector AI demonstration.

**Validated on:** editorial and consulting-artifact review, 2026-07-25.

---

## Step 0: Set up your publication repository

On your **lab server**, as **ec2-user**:

```
mkdir -p ~/thought-leadership/{articles,explainers,summaries,diagrams,case-studies,policy-briefs,talks,videos,tools,templates}
```

The `mkdir -p` command creates the whole tree. Keep everything under version control so you have a record of every draft and revision.

Then create a tracker:

```
vi ~/thought-leadership/PUBLICATION-TRACKER.md
```

Use the tracker template from the Tier 17 USE phase. This is how you hold yourself to the publication target.

---

## The artifact types (worked structure for each)

Every artifact below has a required shape. The USE phase provides fill-in templates; here you produce the real, defensible pieces.

### Technical article
One idea, well argued, grounded in real work or a real source.
- Hook: the problem, concretely.
- Claim: what you are asserting, specifically.
- Evidence: from your work, data, or cited sources (no hallucinated citations).
- Method: what others can reuse.
- Limits: where it does not apply.
- Takeaway: the one thing to remember.
- 800-2000 words. Diagrams where they clarify.

### AI-governance explainer
A framework or concept (NIST AI RMF, ISO/IEC 42001, human oversight) made clear for a stated audience.
- Who this is for (executive / technical / policymaker).
- The concept in one plain paragraph.
- Why it matters to that audience.
- How it works, in their language.
- What to do Monday morning.

### Research summary
A distillation of a body of work (yours or the field's) into decision-useful form.
- Question addressed.
- What is known.
- What is contested.
- What is unknown.
- Sources.

### Architecture diagram
A clean, executive-legible diagram of a system or method.
- One diagram, one message.
- Labeled components and data flows.
- Trust boundaries and where sensitive data does and does not go.
- A caption that states the takeaway.

### Case study
A real engagement, anonymized, with method and results. (See the USE worked example.)
- Context (anonymized client and problem).
- Approach (the method you applied).
- What happened (results, honestly, including what did not work).
- Lessons and reusable method.
- Permission obtained; identifying detail removed.

### Policy brief
A decision-ready summary for leadership or policymakers.
- The decision at hand.
- Options with trade-offs.
- Recommendation.
- Risks and how to manage them.
- One page if possible; two maximum.

### Conference presentation
The theme presented and defended live.
- A single clear argument.
- Slides that support, not replace, the talk.
- A recorded demo backup (see the talk-failure SURVIVE scenario).
- Anticipated tough questions with prepared answers.

### Short educational video
A concept taught in three to seven minutes.
- One learning objective.
- Script first, then record.
- Show, do not just tell.
- Captions for accessibility.

### Open-source tool
A method made reusable by others.
- Working code that solves a real problem.
- A clear README: what it does, how to run it, its limits.
- A license.
- Example usage.
- For the target: an AI-governance toolkit (assessment scripts, policy templates, checklists).

### Template
A reusable artifact others can fill in (like the templates you are reading).
- A blank structure with guidance in brackets.
- At least one worked example alongside it.

---

## Step 1: Produce your flagship ladder first

Pick your flagship theme from Concepts Module 17.1 (recommended: responsible AI adoption in African public institutions). Climb the ladder for it:

1. Two or three technical articles on facets of the theme.
2. One explainer on the governance framework you use.
3. One case study from a real engagement (your Tier 16 or Tier 18 work, anonymized).
4. One policy brief for public-sector leadership.
5. One conference talk built from the above.
6. The open-source governance toolkit.
7. One peer-reviewed or doctoral submission that ties it together.

Then add breadth: articles across the other themes to reach the 12-article target.

---

## Step 2: Route each artifact to the right channel

Use the channel table from Concepts Module 17.2. A policy brief goes to leadership; a method you want cited goes to peer review; a quick idea goes to your blog.

---

## Exit standard for the BUILD

The first tranche of the publication target is live: technical articles plus at least one published case study, each grounded and defensible. Every published claim can be backed with evidence if challenged. No fabricated citations exist anywhere in the set.

---

Prof. Happy (SUTA Labs)
