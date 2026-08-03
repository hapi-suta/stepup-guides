# INTERVIEW: Phase 0 Orientation

**Phase 0 - Interview preparation**

These are the questions a client or hiring manager might ask at the very start of an AI consulting engagement. They test whether you can explain foundational ideas clearly - especially to non-technical people - and whether you work in a disciplined, reproducible way.

For each question below you get:
- **The question** as it might be asked.
- **A strong answer** you can adapt in your own words.
- **How to answer** - the technique that makes the answer land.
- **Why they ask this** - the real thing they are testing.

Practice saying these out loud. In a real interview, aim for a clear 60-90 second answer, not a memorized script.

---

## Q1. Explain the difference between MLOps and LLMOps to a non-technical executive.

**Strong answer:**
"Think of MLOps as the discipline of running any machine-learning system reliably in production - the same way DevOps keeps normal software running. It covers preparing data, training models, deploying them, and watching them so they keep performing as the world changes.

LLMOps is a specialized version of that for large language models, the technology behind tools like ChatGPT. Language models bring a few new challenges that ordinary ML does not: you often use a model someone else trained, so instead of training you focus on writing good prompts; you pay per word (token), so cost management matters a lot; and the output is open-ended text, which is harder to measure than a yes/no prediction, so evaluation is different.

So MLOps is the general playbook, and LLMOps is the chapter of that playbook written specifically for language models - same goal of reliability, but with prompts, token costs, and text evaluation front and center."

**How to answer:** Anchor to something the executive already knows (DevOps, or "keeping software running"). Give MLOps first as the general case, then LLMOps as the specialization, and name only two or three concrete differences (prompts, cost per token, evaluation). Avoid jargon; when you must use a term like "token," define it in the same breath.

**Why they ask this:** They want to know you can translate technical concepts for the people who actually approve budgets. Consultants who cannot explain their work simply do not get hired.

---

## Q2. What is the difference between AI, ML, and generative AI?

**Strong answer:**
"They are nested, like circles inside circles. AI - artificial intelligence - is the biggest circle: any technique that gets a computer to do something that normally needs human intelligence. Machine learning is a circle inside that: instead of a programmer writing exact rules, the system learns patterns from examples in data. Generative AI is a smaller circle inside machine learning: models that create brand-new content - text, images, code - rather than just sorting or predicting.

A quick example of each: a rule-based fraud filter is AI; a spam classifier that learned from millions of emails is ML; a tool that writes a first draft of that email for you is generative AI."

**How to answer:** Use the nested-circles image - it is instantly memorable and correct. Then give one concrete example per layer so it is not abstract. Keep the definitions to one sentence each.

**Why they ask this:** People throw these terms around interchangeably. Getting the relationship right shows you understand the field's structure and will not oversell "AI" when you mean a simple rule.

---

## Q3. How do you keep your work reproducible?

**Strong answer:**
"Reproducibility means someone else - or me, six months later - can run my work and get the same result. I build it in from the start with a few habits.

First, everything goes in version control with git, so there is a single source of truth and a history of every change. Second, I pin my dependencies: each project has its own virtual environment and a requirements file that lists exact package versions, so the environment can be rebuilt anywhere. Third, I never hard-code secrets or absolute paths - configuration comes from environment variables, so the same code runs on any machine. Fourth, I keep an experiment log and a README with the exact steps to run the project from scratch. And where it matters, I containerize with Docker so the whole environment ships together.

The test I hold myself to: could a new teammate clone the repo and reproduce my result following only the README? If not, it is not done."

**How to answer:** List concrete, checkable practices (git, pinned dependencies, no hard-coded secrets, README, Docker) rather than saying "I'm careful." End with a crisp definition of "done" - the clone-and-run test - which shows you have a standard, not just good intentions.

**Why they ask this:** Non-reproducible work is a liability for a client - it breaks when you leave. They are checking that you are a professional who hands over maintainable systems, not one-off magic.

---

## Q4. Why do you use a virtual environment for each project?

**Strong answer:**
"Different projects often need different, sometimes conflicting, versions of the same package. If I install everything into one shared Python, one project's upgrade can silently break another. A virtual environment gives each project its own isolated set of packages, so they never interfere. It also makes the project portable: I can list exactly what it needs in a requirements file and rebuild that same environment on any machine. It is a small habit that prevents a whole category of 'it works on my machine' problems."

**How to answer:** Lead with the concrete pain it prevents (version conflicts, "works on my machine"), then the two benefits: isolation and portability. Short and practical.

**Why they ask this:** It is a quick check that you understand basic Python project hygiene - a red flag if a candidate installs everything globally.

---

## Q5. A client asks, "Should we build our own AI model or use an existing one?" How do you start answering that?

**Strong answer:**
"I start by asking what problem they are solving and what they already have, not with a technology. For most business problems today, the fastest, cheapest path is to use an existing model - a hosted large language model or an open one - and adapt it with good prompts or by feeding it the client's own data. Building and training a model from scratch is expensive, slow, and only worth it when you have a lot of proprietary data and a need that off-the-shelf models genuinely cannot meet. So my default recommendation is 'use and adapt first,' and I only propose custom training after we have proven the simpler approach is not enough. That keeps their risk and cost low while we learn what actually works."

**How to answer:** Show you lead with the problem, not the tech. State a sensible default (use/adapt existing before building), name the condition that would change your mind (lots of proprietary data, off-the-shelf falls short), and frame it as managing the client's cost and risk.

**Why they ask this:** They are testing judgment and business sense, not model trivia. A good consultant steers clients away from expensive over-engineering.

---

## Q6. How would you document a project so someone can pick it up after you leave?

**Strong answer:**
"I keep documentation next to the code and treat it as part of the deliverable. Every project has a README that states the problem it solves, the approach, an architecture description with a simple diagram, and - most importantly - the exact steps to set up and run it from scratch. I also keep an experiment log so the reasoning behind decisions is not lost, and I comment the non-obvious parts of the code. I use a standard project template so every engagement looks the same and nobody has to hunt for information. The bar is that a new person can go from an empty machine to a running system using only what I wrote down."

**How to answer:** Name the specific artifacts (README, run-from-scratch steps, architecture diagram, experiment log, template) and end with the "empty machine to running system" bar. Concrete beats vague.

**Why they ask this:** Handover is where consulting engagements succeed or fail. They want proof you leave clients self-sufficient, not dependent on you.

---

## Practice tips

- Say each answer out loud until it is natural in your own words. Do not memorize word for word.
- For any concept, have one plain-language analogy ready (nested circles, DevOps for software).
- If you do not know something, say what you would do to find out. Honest and methodical beats bluffing.
- Keep answers to 60-90 seconds. Pause, answer the actual question, then stop.
