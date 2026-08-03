# Concepts 6.1: LLM Foundations

**Tier 6 - Generative AI and large language models.** This is a teaching reference, not a lab. Read it, keep the ideas in your head, and come back to it when a BUILD or USE step mentions a term you want to double-check. You do not need to memorize anything. You need a clear mental model of what a large language model actually is, so that when a client asks "can it just do X?" you can answer honestly.

**Who this is for:** you are a DBA moving into AI consulting. You already reason about systems, inputs, outputs, and failure modes. An LLM is one more system - a very large, very useful, and slightly unpredictable one. We build the picture up from what you already understand.

---

## 1. What a large language model is

A large language model (LLM) is a program that predicts the next chunk of text, one chunk at a time, based on all the text it has seen so far. That is the whole trick. Everything else - answering questions, writing code, summarizing a document - is that one prediction repeated over and over.

Think of it like autocomplete on your phone, but trained on an enormous amount of text and far better at keeping context. When you type "the capital of France is", the model has learned that "Paris" is overwhelmingly the likely next word, so that is what it produces.

The key consultant takeaway: the model does not "look up" facts in a database. It predicts likely text. Most of the time the likely text is also the true text, because the truth appeared often in its training data. But the model is optimizing for "sounds right", not "is right". That gap is where hallucinations live (section 8).

---

## 2. Tokens and tokenization

The model does not read letters or words directly. It reads **tokens**. A token is a small piece of text - often a whole short word, sometimes part of a longer word, sometimes just a space plus a word.

Rough rule of thumb in English: **1 token is about 4 characters, or about 0.75 words.** So 1,000 tokens is roughly 750 words.

**Tokenization** is the step that chops your text into tokens before the model sees it. Why you care as a consultant:

- **Billing is per token**, not per word. Input tokens and output tokens are usually priced differently (output is more expensive).
- **Limits are in tokens.** The maximum size of a request is a token count, not a word count.
- **Code and non-English text tokenize less efficiently** - the same visible length can be many more tokens.

Do not estimate token counts with a generic word count or a tool built for a different model. Each model family has its own tokenizer, and the only accurate count comes from that model's own token-counting endpoint. We use a real one in BUILD.

---

## 3. Training: pretraining, instruction tuning, and preference tuning

Modern LLMs are built in stages. You do not train them yourself - the providers do - but you should understand the stages, because they explain the model's behavior.

**Pretraining.** The model reads a very large amount of text (books, websites, code) and learns to predict the next token. This is where it picks up grammar, facts, reasoning patterns, and world knowledge. It is expensive and done once by the provider. After pretraining, the model is knowledgeable but not yet good at *following instructions* - it will happily continue your text rather than answer your question.

**Instruction tuning (also called supervised fine-tuning).** The model is then trained on many examples of "here is an instruction, here is a good response". This teaches it to behave like an assistant: when you ask a question, it answers rather than rambling.

**Preference tuning (the "RL" stage).** Finally, the model is refined using human (and AI) judgments about which of two responses is better. This is often done with reinforcement learning from human feedback (RLHF) or similar methods. It shapes tone, helpfulness, honesty, and safety - teaching the model to refuse harmful requests and to hedge when unsure.

You will hear "RL" and "RLHF" thrown around. The one-sentence version for a client: *"the model was first taught to predict text, then taught to follow instructions, then taught to prefer the kinds of answers people actually want."*

---

## 4. The context window

The **context window** is the maximum amount of text - measured in tokens - that the model can consider at once. It includes everything: your instructions, the conversation history, any documents you paste in, AND the response the model is generating.

Picture it as the model's desk. Everything it can see to do the current task has to fit on the desk. Anything that falls off the edge is gone - the model has no memory of it.

- **Input tokens** (your prompt + history + documents) plus **output tokens** (the response) must both fit within the window.
- Different models have different window sizes. Current large models offer very large windows (up to around 1 million tokens on the top tier), but bigger is not automatically better - more context can cost more and can dilute the model's focus.
- The model has **no memory between separate calls**. If your app needs the model to "remember" earlier turns, your app has to send the earlier turns back in every request. The API is stateless.

This last point trips up almost every beginner and every client. The chat "remembers" only because the application re-sends the whole conversation each time. That re-sent history is billed every turn.

---

## 5. Inference

**Inference** is the act of running the model to produce output - as opposed to training it. When your app calls the API and gets a response, that is one inference.

Inference is where your money and your latency go in production. Two levers matter:

- **Input size.** More input tokens = more to process = higher cost and slightly higher latency.
- **Output size.** The model generates one token at a time, so a long response takes proportionally longer and costs more.

A consultant designing an LLM feature is really designing the shape of inference: how big is each request, how many requests, how long are the responses.

---

## 6. Sampling: temperature and top-p

At each step, the model does not output a single certain token. It produces a *probability* for every possible next token. **Sampling** is how one token gets chosen from that distribution.

Two dials control sampling. (Note: some newer models remove these dials and steer behavior through prompting and an "effort" setting instead - we cover that in Concepts 6.3. The concept still matters for understanding and for the many models that expose them.)

**Temperature.** Controls randomness.

- **Low temperature (near 0):** the model almost always picks the single most likely token. Output is focused, repeatable, and "safe". Good for extraction, classification, factual answers, code.
- **High temperature (near the top of the allowed range):** the model is more willing to pick less-likely tokens. Output is more varied and creative, but also more prone to going off the rails. Good for brainstorming, creative writing, generating variety.

Note the allowed range depends on the provider. On the Anthropic API, `temperature` accepts `0.0` to `1.0` (a request outside that range is rejected). Other providers use different ranges (OpenAI, for example, allows `0` to `2`), so "high" is relative to the model you are calling - always check that provider's docs (see: docs.anthropic.com API reference; platform.openai.com/docs).

The mental image: temperature is how adventurous the model is allowed to be when choosing its next word.

**Top-p (nucleus sampling).** Instead of considering every possible token, the model considers only the smallest set of top tokens whose probabilities add up to `p` (say 0.9), then samples from just that set.

- **Low top-p (e.g. 0.1):** only the very most likely tokens are eligible. Very focused.
- **High top-p (e.g. 0.95):** a wider set of tokens is eligible. More variety.

Temperature and top-p both control variety, from different angles. A common piece of advice: **change one of them, not both**, so you can reason about the effect. Many providers even reject requests that set both at once.

How to explain this to a client (you will be asked - it is an interview question):

> *"Temperature is a creativity dial. Turn it down and the model gives you the same safe, predictable answer every time - what you want for pulling data out of a document. Turn it up and it explores more unusual wording - what you want for brainstorming taglines. Top-p is a related dial that limits how far off the beaten path the model is allowed to wander. For anything where correctness matters, keep both low."*

---

## 7. What the output looks like, and why "structured output" matters

By default the model returns free-form text. That is fine for a chat reply, but a problem when your application needs to *act* on the answer - store it in a database, branch on it, pass it to another system.

If you ask "is this review positive or negative?", a raw model might reply "This review is quite positive overall, the customer seems happy." Your code cannot easily branch on that.

The fix is **structured output**: you constrain the model to return a specific shape, usually JSON matching a schema you define. Now the reply is `{"sentiment": "positive"}` and your code can use it directly. We build this in BUILD, and it is central to using LLMs as reliable components rather than chat toys. Concepts 6.2 (prompt design) and 6.4 (API development) go deeper.

---

## 8. Hallucinations and limitations

A **hallucination** is when the model produces something false but stated confidently - a made-up citation, a wrong date, an API that does not exist, a fabricated quote. Because the model optimizes for plausible text, a confident falsehood can look exactly like a confident truth.

Why it happens (link it back to section 1): the model predicts likely text, and a plausible-sounding wrong answer can be more likely than "I do not know". The model has no built-in sense of "I am now making this up".

How to reduce hallucinations (this is a classic interview question - memorize the shape of this answer):

1. **Ground the model in real data.** Give it the source documents in the prompt and instruct it to answer only from them. This is the core idea behind retrieval-augmented generation (RAG). If the fact is on the desk, the model does not have to invent it.
2. **Let it say "I do not know".** Explicitly permit and instruct the model to refuse or say it is unsure when the answer is not supported. Models trained with preference tuning will do this if you ask.
3. **Lower the temperature** for factual tasks so the model sticks to its most-confident output.
4. **Ask for citations** and verify them, so a fabricated source is caught.
5. **Keep a human in the loop** for high-stakes outputs (legal, medical, financial).

Other limitations to keep in mind and to set client expectations around:

- **Knowledge cutoff.** The model only "knows" what was in its training data up to a certain date. It will not know about events after that unless you provide the information (via context or a search tool).
- **No true real-time access.** On its own, the model cannot see today's stock price or your live database. It needs a tool or the data pasted in.
- **Math and precise counting** can be shaky - the model predicts text, it does not run a calculator, unless you give it one (a code-execution tool).
- **It is not deterministic by default.** Even at temperature 0, outputs are not guaranteed byte-identical across runs. Do not promise a client "the same input always gives the same output".
- **It reflects its training data**, including biases present there.

The honest consultant framing: an LLM is a brilliant, fast, tireless generalist that occasionally states a confident falsehood and has no memory of your last conversation. Design the system around those two facts and it becomes enormously useful.

---

## Takeaways

- An LLM predicts the next token; everything it does is that prediction repeated. It optimizes for plausible, not true.
- Text is processed as tokens (~4 chars each); billing and limits are in tokens; count them with the model's own tokenizer, never a generic estimate.
- Training goes pretraining -> instruction tuning -> preference tuning (the "RL" stage).
- The context window is the model's desk - everything for the task must fit, and the API has no memory between calls.
- Temperature and top-p control variety; keep them low for factual work, and change one at a time.
- Structured output turns the model from a chat toy into a reliable component.
- Hallucinations are confident falsehoods; reduce them with grounding, permission to say "I do not know", low temperature, citations, and human review.

---

## References

Authoritative sources for the concepts in this document. Model IDs, context-window sizes, and prices change frequently - always confirm the live numbers from the provider's docs before quoting them to a client, and never treat a specific price as an eternal fact.

- Anthropic / Claude docs (tokens, context windows, temperature range 0.0-1.0, sampling, stateless API): https://docs.anthropic.com/
- OpenAI API docs (comparison point for temperature range and sampling): https://platform.openai.com/docs/
- Token rule of thumb (~4 characters / ~0.75 words per token, English, approximate; use the model's own tokenizer for real counts): https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them
- RLHF / preference tuning (training stages): "Training language models to follow instructions with human feedback" (Ouyang et al., InstructGPT): https://arxiv.org/abs/2203.02155

Prof. Happy (SUTA Labs)
