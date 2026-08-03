# Interview: Tier 6 - Generative AI and Large Language Models

**Tier 6 interview prep.** These are the questions an AI-consulting client, a hiring panel, or a skeptical executive will actually ask to see whether you understand LLMs well enough to be trusted with a real budget. Each entry has the question, a model answer in plain language, and "why they ask" so you know what they are really probing.

The skill being tested across all of these is the same: can you explain a powerful, slightly unpredictable technology honestly and clearly to someone who is about to spend money on it? That is the consultant's job.

---

## 1. Explain temperature and top-p to a client.

**Model answer.** Temperature is a creativity dial. Turn it down toward zero and the model gives you its single most likely, most predictable answer every time - that is what you want for pulling data out of a document or classifying a ticket, where you need the same reliable output. Turn it up and the model is willing to pick less-likely words, so it explores more - good for brainstorming taglines or drafting varied copy, but riskier. Top-p is a related dial: instead of letting the model consider every possible next word, it restricts the choice to the smallest set of most-likely words that together cover, say, 90% of the probability. Low top-p keeps it very focused; high top-p lets it wander wider. The practical advice: for anything where correctness matters, keep both low, and change only one of them at a time so you can actually reason about the effect. Some newer models even hide these dials and let you steer with the prompt and a "how hard to think" setting instead.

**Why they ask.** These are the two knobs everyone has heard of and almost no one can explain in business terms. They want to see you can translate a technical parameter into "here is what it does to your output and here is when to use it" without hand-waving or jargon.

---

## 2. How do you reduce hallucinations?

**Model answer.** A hallucination is the model stating something false with total confidence, because it optimizes for plausible-sounding text, not for truth. You reduce them with a stack of techniques, not one trick. First and most important: ground the model in real data - put the actual source documents in the prompt and instruct it to answer only from them. That is the core of retrieval-augmented generation, and it works because the model no longer has to invent the fact - it is right there on the page. Second, explicitly permit and instruct the model to say "I do not know" when the answer is not supported; a well-trained model will do that if you ask. Third, lower the temperature for factual tasks so it sticks to its most confident output. Fourth, ask for citations and then verify them, so a fabricated source gets caught. And for anything high-stakes - legal, medical, financial - keep a human in the loop to review before it goes out. No single method makes hallucinations disappear; together they push the risk down to something manageable.

**Why they ask.** Hallucinations are the number one reason executives are nervous about LLMs, and rightly so - a confident wrong answer in production erodes trust and can cause real harm. They want to know you take the risk seriously and have concrete, layered mitigations, not a shrug or a promise that "the model is smart enough".

---

## 3. Why should we avoid locking into one provider?

**Model answer.** The LLM market moves fast - prices drop, better models launch, and the best choice today may not be the best choice in six months. Lock-in means that switching would be so painful you stay put even when it no longer makes sense, and that costs you money and capability over time. It also concentrates risk: if your one provider has an outage, a price hike, or a policy change, you have no escape. So I design against it from day one. All model calls go through one thin interface, so swapping providers is a one-file change instead of a rewrite. Credentials come from environment variables, never hardcoded. Prompts live in a portable, versioned library with a regression test set, so I can re-validate them on a new model quickly. And I keep a written exit strategy - which alternate provider we would move to and what it would take. None of this is expensive to build up front, and it turns "we are trapped" into "we can move in days if we need to". That optionality is worth a lot to a client.

**Why they ask.** Vendor lock-in is a classic enterprise procurement fear, and it is a place where a naive builder quietly paints the client into a corner. They want to see you think about the client's long-term freedom and total cost, not just getting a demo working with whatever SDK was easiest.

---

## 4. How would you estimate the monthly cost of an LLM feature?

**Model answer.** I estimate it bottom-up from tokens, because that is how you are billed - not by words or by request, but by tokens, where a token is roughly four characters. For one call, the cost is the input tokens times the input price plus the output tokens times the output price, and output tokens are usually several times more expensive than input. I get the average input and output token counts by running a real sample of the client's data through the model's own tokenizer - never a generic estimate, which is wrong especially for code and non-English text. Then I multiply that per-call cost by the expected number of calls per month. I also account for two things people forget: in a chat, the whole conversation history is re-sent and re-billed every turn, so long conversations get more expensive; and prompt caching (for shared prefixes) and batch processing (for non-urgent work) are big discount levers that can cut the bill substantially. Finally I present the number with every assumption written down - calls per month, average tokens, prices as of a specific date - so the client can see what would change it.

**Why they ask.** Cost estimation is often the first concrete deliverable of an engagement, and a wrong estimate destroys credibility fast. They want to see you can produce a defensible number with the assumptions exposed, and that you know the non-obvious cost drivers (re-sent history, output-token weighting, caching, batching).

---

## 5. What is the context window, and why does it matter?

**Model answer.** The context window is the maximum amount of text, measured in tokens, that the model can consider at once - and it includes everything: your instructions, the conversation history, any documents you paste in, and the response being generated. Think of it as the model's desk: everything needed for the current task has to fit on the desk, and anything that falls off the edge is simply gone. Two consequences matter for a client. First, the API has no memory between separate calls - a chatbot "remembers" earlier turns only because the application re-sends the whole conversation each time, and that re-sent history costs tokens every turn. Second, bigger is not automatically better: a larger window lets you include more context, but it can cost more and can dilute the model's focus. So part of designing a feature is deciding how much context each request really needs.

**Why they ask.** The context window and the stateless API are the two facts beginners get wrong most often, and getting them wrong leads to broken designs and surprise bills. They want to confirm you understand what the model can actually "see" and that memory is something your application provides, not something the model has.

---

## 6. What is tool (function) calling, and why is it important?

**Model answer.** Tool calling lets the model ask your code to run a function and hand back the result, so the model can do things it cannot do on its own - look up a live value, query a database, do exact arithmetic, call another API. The flow is: you describe the available tools to the model, like well-documented function signatures; the model, instead of answering directly, says "call this function with these arguments"; your code actually runs it; and the model uses the result to finish its answer. The key point for a client is the boundary: the model never runs your code, it only requests a call, and your application decides whether to execute it. That boundary is exactly where you put security and approvals - you never let the model trigger a destructive action without a gate. Tool calling is also the foundation of agents: a model in a loop, calling tools until a task is done.

**Why they ask.** Tool calling is how LLMs move from "chatbot" to "does useful work in our systems", so it is central to almost any serious build. They want to see you understand both the capability and the security boundary - that you would not hand the model the keys to the database without a gate.

---

## 7. What is structured output and why would you use it?

**Model answer.** By default the model returns free-form text, which is fine for a chat reply but a problem when your code needs to act on the answer - store it, branch on it, pass it downstream. Structured output constrains the model to return a specific shape, usually JSON matching a schema you define, so instead of a sentence you get a clean object your code can use directly. On models that support it, the API will actually guarantee the output is valid JSON of that shape, which eliminates a whole class of bugs where the model wraps the answer in prose and breaks your parser. Where a hard guarantee is not available, you fall back to a very explicit "respond with only this JSON, nothing else" instruction plus defensive parsing. It is the single most important technique for turning an LLM from a chat toy into a reliable component in a pipeline.

**Why they ask.** Real integrations depend on parseable output, and "the model returned something my code could not read" is one of the most common production failures. They want to see you know how to make an LLM behave like a dependable API rather than a text generator you have to babysit.

---

## 8. A provider goes down in the middle of the business day. What happens to our feature, and how do you design so it does not?

**Model answer.** If the feature depends on a single provider with no fallback, it goes completely dark - every request fails and users are stuck, because one provider is a single point of failure. Providers do have outages; that is normal, so I design for it rather than hope against it. The fix is graceful degradation: the app tries the primary provider, and on any failure - down, timeout, overloaded, or even a refusal - it automatically falls back to a second provider, which might be a different vendor, a different tier, or a self-hosted model. Because all my model calls already go through one thin provider interface, adding fallback is cheap - the backup is just another provider behind the same interface. I always log why the fallback happened, so a silent failure never hides an ongoing outage. The result is that a provider outage becomes a brief degradation instead of a full stop.

**Why they ask.** Availability is a board-level concern, and "our AI feature was down all afternoon" is a headline no one wants. They want to see you treat the LLM as an unreliable remote dependency - like any external service - and build resilience in from the start.

---

## 9. Our LLM bill was ten times what we expected last month. What likely went wrong and how do you prevent it?

**Model answer.** A bill that size almost always comes from one of a few causes: a runaway loop or a bad batch that called the model far more times than intended; long conversations re-sending and re-billing their whole history every turn; using a top-tier expensive model for a task a cheaper one would handle; or simply high volume with no cost controls in place. The prevention is a stack of controls. First, a hard budget cap that actually stops the run before it exceeds a limit - not just a dashboard you look at afterward. Second, token counting so you know a request's cost before you send it. Third, caching: if many requests share a large unchanging prefix, or repeat the same prompt, you cache it and stop paying full price for the same work - that alone can cut most of the bill. Fourth, batch mode for anything that does not need an instant answer, which is often around half price. And fifth, right-sizing the model to the task. Together those turn an unbounded bill into a predictable, capped one.

**Why they ask.** Cost surprises are one of the fastest ways an AI project loses executive support. They want to see you treat spend as something to actively control - with budgets that halt, not just monitor - and that you know the real levers (caching, batching, model choice, capping loops).

---

## 10. Walk me through how you would handle rate limits in production.

**Model answer.** Every provider caps how much you can send - requests per minute and tokens per minute - and when you exceed it you get a 429, "too many requests". The wrong responses are to crash on it or to immediately hammer the API again. The right response is retry with exponential backoff and jitter: wait a bit and retry, doubling the wait each time so an overloaded service gets room to recover, and add a small random amount to each wait so many clients do not all retry in lockstep and cause a thundering herd. If the provider sends a Retry-After header telling you exactly how long to wait, honor it. Cap the number of retries so you fail cleanly instead of forever. And design to avoid hitting the limit in the first place - pace or batch your requests to stay under the ceiling, and size your account's tier for the feature's real peak throughput. Rate limits are one of the most common reasons a demo that worked falls over under real load, so I plan for them rather than discover them.

**Why they ask.** This is the difference between someone who has only made a demo and someone who has run an LLM feature in production. They want to see you know 429s are inevitable, that backoff-with-jitter is the correct pattern, and that you size for real throughput instead of finding the limit the hard way.

---

## 11. What is the difference between using a hosted API, a cloud platform, and self-hosting an open model? When would you pick each?

**Model answer.** A hosted API - calling a provider directly over the internet and paying per token - is the fastest to value: zero infrastructure, always the latest models, elastic scale. It is the default for most clients most of the time. The trade-off is that your data leaves your network under the provider's terms, and you depend on their uptime and pricing. A cloud platform like a big provider's managed AI service gives you the same "someone else runs it" convenience but inside a cloud you may already trust, with that cloud's identity, billing, networking, and compliance certifications - a great fit for a regulated client who needs the data-handling story to stay inside AWS or Azure. Self-hosting an open-weight model on your own hardware means the data never leaves your environment and there is no per-token vendor bill, which suits very high volume, strict data residency, or air-gapped work - but you take on the operations, scaling, and updates, and smaller self-hosted models are usually less capable than the top hosted ones. So I pick by the client's constraints: fastest to value, trusted boundary, or maximum data control and volume economics.

**Why they ask.** Deployment choice drives cost, compliance, and control all at once, and it is a decision the client will lean on you for. They want to see you can match the deployment model to the client's real constraints - regulatory, volume, budget - rather than reaching for the same answer every time.

---

Prof. Happy (SUTA Labs)
