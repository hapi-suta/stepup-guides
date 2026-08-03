# Concepts 6.4: API Development

**Tier 6 - Generative AI and large language models.** Teaching reference. This is the engineering layer: how you actually call an LLM from code in a way that is reliable, affordable, and production-ready. Concepts 6.1-6.3 gave you the mental model, prompt craft, and provider landscape. This document turns them into the concrete API mechanics you will use in BUILD, USE, and SURVIVE.

**Who this is for:** DBAs moving into AI consulting. You already write code that talks to a database with connection pooling, retries, and error handling. An LLM API is another remote dependency - treat it with the same discipline: handle failures, watch costs, respect limits, and never trust a single call to always succeed.

**A note on keys and mocks.** Every real LLM call needs an API key that the *client* (or you, for a real project) supplies via an environment variable - `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and so on. The labs read the key from the environment and degrade gracefully with a clear "set your API key" message when it is absent. The SURVIVE scenarios never call a real paid API at all - they run a **local mock LLM server** so you can test the resilience logic (backoff, budgets, fallback) for free. Wherever a real key is actually required, the lab says so explicitly.

---

## 1. The basic request/response

Every LLM API call is fundamentally the same shape, whichever provider or SDK:

1. You create a client, authenticated with an API key from the environment.
2. You send a request: which model, the messages (system + user), and a `max_tokens` cap on the response length.
3. You get back a response object containing the generated text plus metadata (token usage, why it stopped).

You always read the key from the environment, never hardcode it:

```python
import os
api_key = os.environ.get("ANTHROPIC_API_KEY")
if not api_key:
    raise SystemExit("Set your API key: export ANTHROPIC_API_KEY=... (see the lab intro)")
```

`max_tokens` is the maximum length of the *response*. Set it big enough that the answer is not cut off, but not wastefully large. If a response stops because it hit `max_tokens`, the output is truncated and you must raise the cap or stream.

---

## 2. Streaming

By default you wait for the entire response, then get it all at once. **Streaming** delivers the response token-by-token as it is generated.

Use streaming when:

- The output is long or `max_tokens` is high (streaming avoids request-timeout problems on long generations).
- You want a responsive UX - text appearing live instead of a long blank pause.

The trade-off is slightly more code to handle the stream of events, and you only know the final token count at the end. For short, non-interactive calls (classification, extraction) non-streaming is simpler and fine.

---

## 3. Structured outputs

Covered conceptually in 6.1/6.2; here is the mechanic. Rather than parsing free text and hoping, you tell the API to return output matching a JSON schema you define. The API then guarantees (or strongly enforces) that the response is valid JSON of that shape.

Two related features you will meet:

- **Response format / schema constraint** - the whole response must be JSON matching your schema.
- **Strict tool use** - a tool's arguments are guaranteed to match the tool's declared schema.

For any output your code will act on programmatically, prefer a schema-enforced structured output. It removes an entire category of "the model wrapped the JSON in prose and broke my parser" bugs. Note it is not available identically on every model/provider, so verify support (Concepts 6.3) - and where it is not available, fall back to a very explicit "respond ONLY with this JSON, nothing else" prompt plus defensive parsing.

---

## 4. Tool / function calling

**Tool calling** (also called function calling) lets the model ask *your* code to run a function and hand back the result. This is how an LLM breaks out of its own head to do things it cannot do alone: look up a live value, query a database, do exact arithmetic, call another API.

The flow:

1. You describe the available tools to the model - name, description, and an input schema (just like a well-documented function signature).
2. The model, instead of answering directly, may respond "call `get_weather` with `{city: 'Lagos'}`".
3. **Your code** runs the actual function and sends the result back.
4. The model uses the result to produce its final answer.

Key points for the consultant:

- The model never runs your code. It *requests* a call; your application executes it. That boundary is where you enforce security and approvals - never let the model trigger a destructive action without a gate.
- Tool descriptions are prompts. Be prescriptive about *when* to call the tool, not just what it does.
- This is the foundation of "agents": a model in a loop, calling tools, until the task is done.

---

## 5. Error handling and retries

An LLM API is a network dependency and it *will* fail sometimes. Robust code handles at least these categories:

- **Authentication errors (401/403):** bad or missing key. Not retryable - fix the key. This is where the "set your API key" message lives.
- **Bad request (400):** malformed request - wrong parameter, unsupported option for that model. Not retryable - fix the request.
- **Rate limit (429):** you are sending too fast. **Retryable** after a delay (section 8).
- **Server errors (500/529):** the provider had a transient problem or is overloaded. **Retryable** with backoff.
- **Refusals:** a successful response where the model declined (a valid outcome, not an exception). Detect it and handle it - do not assume every 200 response is usable.
- **Timeouts / connection errors:** network trouble. Retryable.

The golden rule: **never silently swallow an error.** Log it with context (which request, which model, the request id if present), and either retry the retryable ones or surface the rest clearly.

---

## 6. Token counting

Because billing and limits are in tokens (Concepts 6.1), you often need to know a request's token count *before* sending it - to estimate cost, to stay under a limit, to enforce a budget.

Use the model's own token-counting facility. Never estimate with a generic word count or a tokenizer built for a different model family - the numbers are wrong, often badly, for code and non-English text. In BUILD you count tokens with a real tokenizer and use the count to estimate cost.

---

## 7. Rate limits

Providers cap how much you can send: requests per minute (RPM) and tokens per minute (TPM), sometimes tokens per day. Exceed a cap and you get a 429.

As a consultant designing a feature you must size for the client's real throughput:

- Estimate peak requests-per-minute and tokens-per-minute for the feature.
- Check the account's limits at its tier.
- If the feature would exceed them: request a higher tier, add queuing/batching, or spread load.

Rate limits are one of the most common reasons a demo that worked fine falls over in production. Design for them, do not discover them.

---

## 8. Retries with backoff

The correct response to a 429 or a 5xx is not "fail" and not "hammer it again immediately" - it is **retry with exponential backoff and jitter**:

- **Exponential backoff:** wait longer after each failed attempt - 1s, then 2s, then 4s, and so on. This gives an overloaded service room to recover instead of piling on.
- **Jitter:** add a small random amount to each wait, so many clients retrying at once do not all retry in lockstep (a "thundering herd").
- **A cap** on the number of retries and on the maximum wait, so you fail cleanly instead of retrying forever.
- Respect a `retry-after` header if the provider sends one - it tells you exactly how long to wait.

Most official SDKs do basic backoff for you. You still need to understand it, tune it, and sometimes implement it - which is exactly what the rate-limit SURVIVE scenario has you prove against a mock server that returns 429s.

---

## 9. Prompt caching

If many of your requests share a large, unchanging prefix - a big system prompt, a long document, a fixed set of few-shot examples - you can **cache** that prefix so you are not billed full price to reprocess it every time.

- Cached reads cost a small fraction of a normal input token; cache writes cost a little extra.
- Caching is a *prefix* match: the cached part must be byte-identical each time and must come first. Anything that changes (a timestamp, the user's specific question) goes *after* the cached portion.
- Big potential savings for high-volume features with a shared context - one of the first cost levers a consultant reaches for.

---

## 10. Batch processing

For work that does not need an instant answer - overnight classification of a backlog, bulk summarization, offline enrichment - many providers offer a **batch** mode: submit many requests at once, get results back within a window (often up to a day), typically at a large discount (frequently around half price).

Rule of thumb: if it can wait, batch it. If a user is staring at a screen, do not. Interactive = real-time API; bulk = batch.

---

## 11. Cost estimation

Bringing tokens and prices together, the estimate for a single call is:

```
cost = (input_tokens  x input_price_per_token)
     + (output_tokens x output_price_per_token)
```

Then multiply by the expected number of calls. Remember:

- Output tokens are usually several times more expensive than input tokens.
- Conversation history is re-sent (and re-billed) every turn - a long chat gets more expensive with each message.
- Prompt caching and batching are the two biggest discount levers.

Estimating monthly cost for an LLM feature is a standard interview question and a standard first deliverable. The shape:

```
monthly_cost = calls_per_month
             x (avg_input_tokens  x input_price
               + avg_output_tokens x output_price)
```

Get the average token counts from real samples (using the token counter), get the prices from the provider (verify current numbers), and show the client the number with the assumptions written down.

---

## 12. Model fallback

For resilience, do not depend on one model always answering. **Model fallback** means: if the primary model fails, is rate-limited, is overloaded, or refuses, automatically try a secondary model (which may be a different tier or a different provider).

- Combined with the provider abstraction (Concepts 6.3), fallback is just "try provider A; on failure, try provider B".
- It directly improves availability - a provider outage no longer takes your feature down.
- Some platforms offer built-in fallback; you can also implement it yourself in the abstraction layer.

Fallback is the payoff of everything else in this document: env-var keys, a clean provider interface, error detection, and a mock you can test against. The provider-outage SURVIVE scenario has you build and prove exactly this - graceful degradation to a second provider (or the mock) when the first fails.

---

## Takeaways

- Every call is: client (key from env) -> request (model, messages, max_tokens) -> response (text + usage + stop reason). Read the key from the environment; degrade with a clear message when it is missing.
- Stream long or interactive responses; keep short non-interactive calls simple.
- Use schema-enforced structured outputs for anything your code acts on; fall back to strict "JSON only" prompting where unavailable.
- Tool/function calling lets the model ask your code to act - your app runs the function; that boundary is where security lives.
- Handle every error class explicitly; never swallow errors. Retryable: 429, 5xx, timeouts. Not: 401/403, 400. Refusals are successful responses you must detect.
- Count tokens with the model's own tokenizer; size for rate limits; retry with exponential backoff + jitter + a cap.
- Cut cost with prompt caching (shared prefixes) and batch processing (non-urgent work); estimate cost as tokens x price x calls, assumptions written down.
- Add model fallback so one provider's failure does not take the feature down - the payoff of a clean provider abstraction.

---

## References

Authoritative sources used to fact-check the API mechanics in this document. Prices, discounts, and feature availability change - confirm current values from the provider docs before quoting them to a client.

- Anthropic Messages API (request/response shape, `max_tokens`, streaming, tool use): https://docs.anthropic.com/en/api/messages
- HTTP error codes and retry guidance (429 rate limit and 5xx/529 overloaded are retryable; 400/401/403 are not; honor `retry-after`): https://docs.anthropic.com/en/api/errors
- Tool / function calling (the model requests a call; your code runs it): https://docs.anthropic.com/en/docs/build-with-claude/tool-use/overview and https://platform.openai.com/docs/guides/function-calling
- Structured outputs / JSON schema enforcement: https://docs.anthropic.com/en/docs/build-with-claude/structured-outputs and https://platform.openai.com/docs/guides/structured-outputs
- Token counting (use the model's own tokenizer, not a generic estimate): https://docs.anthropic.com/en/docs/build-with-claude/token-counting
- Prompt caching (prefix match; cached reads cost a small fraction of normal input tokens; writes cost a little extra): https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching
- Batch processing (asynchronous; roughly 50% cost discount): https://docs.anthropic.com/en/docs/build-with-claude/batch-processing
- Exponential backoff with jitter (the "thundering herd" fix): https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/

Prof. Happy (SUTA Labs)
