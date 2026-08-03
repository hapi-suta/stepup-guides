# Interview: Tier 13 - Cloud AI Platforms

**Tier 13 interview prep.** These are the questions an AI-consulting client, a
hiring panel, or a skeptical CIO/CISO will actually ask to see whether you can be
trusted to put their AI on a cloud - securely, observably, and without trapping
them. Each entry has the question, a model answer in plain language, and "why they
ask" so you know what they are really probing.

The skill being tested across all of these is the same: can you deploy AI on a
cloud in a way that is secure, costs what you said it would, keeps the client's
data where it must stay, and lets them leave if they need to? That is the
consultant's job at this tier.

---

## 1. Why AWS as primary, and when would you recommend Azure or GCP?

**Model answer.** I default to AWS because it has the broadest, most mature cloud
and AI stack, and it is what most enterprise clients already run - Bedrock gives
managed access to many foundation models, with knowledge bases, agents,
guardrails, and the surrounding platform (IAM, VPC, S3, KMS, CloudWatch) all in
one place. But the best cloud is usually the one the client already lives in, so I
recommend Azure when the client is Microsoft-centric - they run Microsoft 365,
their identities are already in Entra ID, and they specifically want OpenAI's GPT
models inside their own boundary. I recommend GCP when the client's data gravity
is in BigQuery, because doing AI right next to that data - even from SQL with
BigQuery ML - avoids a whole data-movement project, and when they want Google's
Gemini models. So AWS is my primary and my deepest expertise, but I choose per the
client's existing footprint, their data gravity, the models they want, and their
compliance needs - and whichever I pick, I keep the model calls behind one
abstraction so they are never locked in.

**Why they ask.** Cloud choice drives cost, security, compliance, and staffing all
at once, and clients lean on you for it. They want to see you have a considered
default AND the judgment to override it for the client's reality, rather than
selling the same cloud to everyone.

---

## 2. How do you secure a Bedrock deployment with IAM, VPC, and KMS?

**Model answer.** I layer it. Identity first: the application runs under an IAM
role, never long-lived keys, and that role has a least-privilege policy - permission
to invoke the one model and read the one bucket, scoped to specific ARNs, with no
wildcards like `bedrock:*` on `*`. The most common cloud AI breach is just a
misconfigured policy or an open bucket, so getting this right is most of the
posture. Network next: the app sits in a private subnet of a VPC with no direct
internet exposure, and it reaches Bedrock over a VPC endpoint (PrivateLink) so the
model calls stay on the AWS backbone and never traverse the public internet -
regulated clients often require that. Data next: S3 buckets are private with
account-level Block Public Access on, and everything is encrypted at rest with a
customer-managed KMS key; secrets come from Secrets Manager and are read at
runtime through the role, never hardcoded. Then I put a Bedrock Guardrail in front
of every call to filter denied topics and redact PII, and CloudWatch alarms on
cost and error rate so a problem pages a human instead of showing up on the bill.
Roles not keys, least privilege, private networking, encryption, guardrails, and
alarms - that is a secure Bedrock deployment.

**Why they ask.** This is the concrete, do-you-actually-know-AWS question. A CISO
wants to hear the specific controls and the right order, not "we'll use AWS
security". Naming roles-over-keys, least privilege, VPC endpoints, KMS, and
Secrets Manager unprompted is the signal that you have really done it.

---

## 3. What is vendor lock-in and how do you reduce it across clouds?

**Model answer.** Lock-in is when leaving a vendor - a cloud or a model provider -
would be so painful that the client stays even when it no longer makes sense,
which costs them money and capability and concentrates risk in one provider's
uptime, pricing, and policy. I reduce it from day one with design, not by avoiding
managed services. All model calls go through one thin abstraction, so switching
provider or cloud is a contained change, not a rewrite - in my Tier 13 project the
exact same app deploys to local Docker, AWS Bedrock, and GCP Vertex by changing
only environment variables, no code. Credentials come from env vars or the cloud's
secret manager, never hardcoded. I containerize, so the deployable artifact is
portable across clouds. I keep prompts in a portable, versioned library with a
regression set so I can re-validate quickly on a new provider. And I write down an
explicit exit strategy - which alternate cloud or model we would move to and what
it would take. This is cheap to build up front and turns "we are trapped" into "we
can move in days". That optionality is worth real money to the client.

**Why they ask.** Lock-in is a classic enterprise procurement fear, and it is
exactly where a naive builder quietly paints the client into a corner by wiring
everything to one cloud's SDK. They want to see you protect the client's long-term
freedom and total cost, and that you can do it while still using managed services.

---

## 4. A client says "our data cannot leave the country." How does that change your cloud design?

**Model answer.** Data residency can decide the entire architecture, so I treat it
as a hard constraint checked first, not an afterthought. It is not enough that the
cloud has a data center in the country - the AI service itself (Bedrock, Azure
OpenAI, Vertex) has to be available in that specific region, and the logs and the
stored data have to be pinnable there too, because any one of those leaking
out-of-region breaks the rule. So I map the required geography to each cloud's own
region name, confirm the AI service and its logging and its data storage all
support that region as of a dated snapshot, and disable anything that could route
inference cross-region. Sometimes the honest finding is that no managed AI service
exists in the required region on any cloud - that is common for some African and
smaller-market regions - and then the recommendation changes to a self-hosted
open-weight model on in-region infrastructure, or a documented, regulator-approved
time-limited exception, never a silent cross-region call of citizen data. I hand
the client a residency comparison with the date on it, because a residency claim
without a date is worthless to an auditor.

**Why they ask.** For public-sector, financial, and healthcare clients, residency
is a legal line, not a preference, and getting it wrong is a compliance incident.
They want to see you know residency can override every other factor, that you
check the AI service and not just the cloud, and that you will say "no managed
option qualifies" when that is the truth.

---

## 5. How would you set up cost controls so a runaway job cannot blow the budget?

**Model answer.** A dashboard that tells you about an overspend the next morning is
not a control - by then the money is gone. So I build layered controls with at
least one that actually halts work. First, a hard budget cap in the application
that checks the running spend before each call and stops the run when the next call
would exceed the limit, so a runaway loop or a bad input file cannot blow past it.
Second, the cloud's own guardrails - a CloudWatch or Cloud Monitoring cost alarm
to detect anomalies, and budget actions or account spend limits as a backstop.
Third, the levers that lower the baseline cost: token counting so I know a
request's cost before sending, prompt caching for shared prefixes, batch mode for
non-urgent work (often about half price), and right-sizing the model to the task
instead of defaulting to the most expensive one. The alarm tells you something is
wrong; the cap is what saves you. I always test the cap by simulating a runaway
and proving it halts.

**Why they ask.** Cost surprises are one of the fastest ways an AI project loses
executive support, and "the bill was ten times what you said" ends engagements.
They want to see you treat spend as something to actively cap, not just monitor,
and that you know the difference between a dashboard and an enforced control.

---

## 6. Walk me through what you would monitor for an AI app running on a cloud.

**Model answer.** Beyond the normal web-app metrics, I watch the things specific to
a cloud AI feature. On usage and cost: invocation count, input and output token
usage, and estimated spend, with alarms on anomalies. On performance: model latency
and error rate, including throttling (429s) which signal I am hitting rate limits.
On quality and safety: guardrail blocks and PII redactions, refusal rate, and -
for a RAG feature - groundedness and citation accuracy. On availability: provider
and region health, and how often my failover path activated, because a silent
fallback can hide an ongoing outage. On the platform: this all flows into
CloudWatch (or Azure Monitor / Cloud Monitoring) with dashboards and alarms, and
the logs are pinned in-region if residency requires it. The point is that an LLM
feature has failure modes a normal service does not - cost blowouts, hallucinations,
safety violations, provider outages - so the monitoring has to cover those, not
just CPU and 500s.

**Why they ask.** This separates someone who has only shipped a demo from someone
who has operated an AI feature. They want to hear the AI-specific signals - tokens,
cost, groundedness, safety blocks, throttling, failover - not a generic "we'll use
CloudWatch".

---

## 7. Bedrock versus SageMaker (or Vertex's two halves) - when do you reach for each?

**Model answer.** Bedrock is call-an-API-and-pay-per-token with no servers to run -
it is the fast path and the right default for almost any client who just needs an
LLM feature. SageMaker is the full ML platform: you bring or build models, train
and tune them, and host your own endpoints on infrastructure you configure. I reach
for SageMaker only when the client actually trains custom models or needs to
self-host an open-weight model - for high volume, strict data control, or an
air-gapped requirement. Reaching for SageMaker when Bedrock would do is a classic
over-engineering mistake that adds cost and operational burden for no benefit. On
GCP the same split lives inside one product, Vertex AI - its foundation-model APIs
are the Bedrock-style path and its training-and-hosting side is the SageMaker-style
path - so I use the hosted-model half unless the client genuinely needs custom
training. Match the tool to the need: managed API by default, full platform only
when they build or self-host.

**Why they ask.** Over-engineering the platform is a real and expensive failure
mode, and clients rely on you to right-size. They want to see you default to the
simpler managed service and can articulate the specific conditions that justify the
heavier one.

---

## 8. How do you handle a KMS or Secrets Manager rotation without downtime?

**Model answer.** Rotation is healthy security hygiene, so I design the app to
survive it rather than treating rotation as a risk. The rule is: never pin a
specific secret version or key version in the app. For Secrets Manager, retrieve
the secret by name, which always returns the current version, instead of asking for
a version id that a rotation will retire. For KMS, reference the key by its alias or
key id and let rotation swap the backing material underneath, rather than caching a
specific key version. That way a scheduled rotation is invisible to the app - it
transparently picks up the new key on the next read, with no code change and no
downtime. The failure I have seen and fixed is exactly the opposite: an app pinned
to the old version, so the moment rotation disabled it the app could not read its
key and the feature went dark. I test rotation-survival by rotating in a lower
environment and confirming the app keeps working.

**Why they ask.** Rotation is a control auditors require, and a fragile app turns a
routine rotation into an outage. They want to see you know the specific habit -
read the active version, reference the alias - and that you would test it, not
discover the breakage in production.

---

## 9. A cloud region has an outage during business hours. What happens to the feature, and how do you design so it survives?

**Model answer.** If the feature depends on one region with no failover, it goes
completely dark for the duration - one region became a single point of failure.
Regions do have outages; that is normal, so I design for it. The fix is failover:
the app tries the primary region, and on any failure - down, timeout, throttled -
it fails over to a second region or, for the strongest resilience, a second cloud
entirely. Because all my model calls already go through one abstraction, adding
that failover is cheap - the backup is just another target behind the same
interface, which is exactly what the multi-cloud portability I build enables. I
always log why the failover fired so an ongoing outage is visible and a silent
fallback never hides it. The result is that a regional outage becomes a brief
degradation instead of an afternoon of downtime. For clients who need it, I can go
further with active-active across regions, but even a simple primary-with-failover
turns "we were down all afternoon" into "we barely noticed".

**Why they ask.** Availability is a board-level concern and "our AI was down all
afternoon" is a headline no one wants. They want to see you treat the cloud region
as a dependency that will fail, and that your portability design pays off directly
as cheap failover.

---

## 10. How do Bedrock Guardrails (or Content Safety / Vertex safety filters) fit into a secure deployment, and what are their limits?

**Model answer.** A guardrail is a screening layer you place in front of the model:
it blocks denied topics, filters harmful content and prompt-injection attempts, and
redacts PII, screening both the input before the model sees it and the output before
the user does. On AWS that is Bedrock Guardrails, on Azure it is AI Content Safety,
on GCP it is Vertex's safety filters and grounding - same concept, different knobs.
I wire it so the app cannot bypass it: screen input, call model, screen output, and
return a safe refusal on a block. It is a strong, cheap control and I document
exactly what it blocks so the client and their auditor can see it. But it is not
the whole security story - it is one layer. It does not replace least-privilege IAM,
private networking, encryption, red-teaming (Tier 11), or human review for
high-stakes outputs, and a determined attacker may find phrasings it misses, so I
treat it as defense in depth, not a silver bullet. The honest framing for a client
is: guardrails meaningfully lower the risk of harmful or leaky output, and they sit
inside a stack of other controls.

**Why they ask.** Guardrails are the visible safety feature clients latch onto, and
the risk is that they oversell it as "the AI is safe now". They want to see you can
deploy it correctly, document what it does, AND be honest that it is one layer among
many rather than a complete solution.

---

Prof. Happy (SUTA Labs)
