# Concepts 5.4: Transformer Foundations

**Tier 5 - Deep learning and NLP.** Teaching reference. Everything modern - ChatGPT, Claude, translation, code assistants - runs on one architecture: the **transformer**. You do not need to build one from scratch to be a great AI consultant, but you MUST be able to explain it, size it, and reason about its limits (tokens, context windows, cost). This doc gives you that fluency, building on the neural-network and NLP ideas from 5.1 and 5.3.

**Who this is for:** DBAs who finished Concepts 5.1, 5.2, and 5.3. No prior transformer knowledge assumed.

**No heavy code here.** Transformers are large; training one needs a GPU cluster. This is the concepts reference. Where you would actually run a transformer (fine-tuning, inference on a real model), we flag it clearly as GPU territory.

---

## 1. The problem transformers solved

Sequence models like RNNs (Concepts 5.3) read text one token at a time, carrying a memory forward. Two problems: they are slow (cannot parallelize across tokens), and they forget the beginning of a long document. Transformers fixed both by dropping the one-at-a-time reading and instead looking at **all tokens at once**, letting each token directly consult every other token. That single change unlocked training on enormous data and produced the models we use today.

---

## 2. Attention: the core idea

**Attention** is the transformer's key mechanism. In plain language: when the model processes one word, attention lets it look at all the other words and decide which ones matter for understanding this word right now, then blend in information from those relevant words.

Take "The invoice was paid because it was overdue." To understand "it", the model uses attention to look back and figure out "it" refers to "the invoice", not "paid." Attention assigns a weight to every other word - high weight to relevant words, low weight to irrelevant ones - and mixes them together. It is a learned, context-sensitive lookup: "for this word, which other words should I pay attention to?"

---

## 3. Self-attention

**Self-attention** is attention applied within a single sequence: every token attends to every other token in the same text (including itself). Do this and each token's representation becomes context-aware - "bank" gets a different representation in "river bank" than in "bank account" because it attended to different neighbors. Self-attention is what gives transformers their understanding of context and word relationships, and it is why the same word can mean different things in different sentences.

The cost: every token compares with every other token, so the work grows with the square of the sequence length. Double the text, quadruple the compute. That is a big reason context windows are limited and long inputs are expensive.

---

## 4. Transformer blocks

A **transformer block** is the repeating building unit. Each block contains:

1. A **self-attention** layer (mix in context from other tokens).
2. A small **feed-forward** neural network (the layers from Concepts 5.1, applied to each token).
3. Helpers that keep training stable: residual connections (add the input back to the output) and layer normalization.

Stack many blocks and you get a deep transformer. GPT-style models are dozens of these blocks in a row. Each block refines the token representations a little more. "Deep" here means many blocks.

---

## 5. Encoders and decoders

Transformers come in three flavors depending on which halves they use:

- **Encoder-only** (for example BERT): reads a whole input and builds a rich understanding of it. Great for classification, search, and NER - tasks where you consume text and output a label or an embedding. This is the family closest to the BUILD's job.
- **Decoder-only** (for example GPT, and autoregressive chat models such as Claude): generates text one token at a time, each new token attending to all previous ones. This is what powers chat and text generation. (Note: Anthropic does not publicly document Claude's exact architecture. Grouping it here is a reasonable inference from its autoregressive, generative behavior, not a published fact - if a client presses on internals, say the architecture is not disclosed rather than asserting it.)
- **Encoder-decoder** (for example T5, translation models): the encoder reads the input, the decoder writes the output. Natural for translation - read English, write French.

Knowing which family a task needs is a consultant skill: classification wants an encoder, chat/generation wants a decoder, translation wants encoder-decoder.

---

## 6. Positional information

Self-attention looks at all tokens at once, which means, on its own, it has no idea of ORDER - "dog bites man" and "man bites dog" would look identical. Transformers fix this by adding **positional information** (positional encodings/embeddings) to each token: a signal that says "this is token 1, this is token 2, ..." So the model gets both the meaning of each word AND its position. Without positional information a transformer could not tell word order apart, which for language would be fatal.

---

## 7. Tokens (and why they are not words)

A **token** is the unit a transformer actually reads. Transformers use **subword** tokenization: common words are one token, rare words split into pieces, and no word is ever "unknown." Rough rule of thumb for English: one token is about 4 characters, so roughly 3/4 of a word - "invoice" might be 1 token, "unbelievable" might be 3.

This matters for two practical reasons every consultant hits:

- **Cost and limits are measured in tokens**, not words. A 1,000-word document is roughly 1,300 tokens.
- **Different languages tokenize differently.** French text often uses more tokens than the equivalent English, because the tokenizer was trained mostly on English. A bilingual project pays more tokens for the French half - budget for it.

The token count, not the word count, is what you pay for and what fills the context window.

---

## 8. Context window

The **context window** is the maximum number of tokens a model can consider at once - input plus output combined. If a model has an 8,000-token context window and you feed it a 7,500-token document, only 500 tokens are left for its answer. Feed it a 10,000-token document and it will not fit; you must chunk it.

Why it matters:

- **Long documents must be split** into chunks that fit, then processed piece by piece (this is where RAG and chunking strategies come from).
- **Bigger context costs more** - both money (more tokens) and time (self-attention is quadratic in length).
- **A bilingual document uses more tokens** for the same content, so it fills the window faster.

When a client asks "can it read our 200-page contract?", the honest answer starts with "how many tokens is that, and what is the model's context window?"

---

## 9. Pretraining

**Pretraining** is the first, enormous training phase where a model learns language in general from a giant pile of raw text. The typical task is simple: predict the next token (for decoders) or fill in a masked token (for encoders). No human labels are needed - the text is its own answer key. After pretraining, the model has absorbed grammar, facts, reasoning patterns, and multiple languages.

Pretraining is astronomically expensive: thousands of GPUs for weeks, millions of dollars. **You will never pretrain a model as a consultant.** You use one that someone else pretrained. But you must understand it, because it explains what the model already knows and where its knowledge cutoff and biases come from.

---

## 10. Fine-tuning

**Fine-tuning** takes a pretrained model and trains it a little more on YOUR specific, labeled data so it specializes. You keep all the general language ability from pretraining and adjust it toward your task - classifying your document types, matching your company's tone, handling your domain jargon.

Fine-tuning needs far less data and compute than pretraining (hundreds to thousands of examples, hours not weeks), but for a real transformer it still needs a GPU. **This is a spot a real project uses a GPU.** Techniques like LoRA make it cheaper by training only a small add-on set of weights, but it is still GPU work. The pretraining-vs-fine-tuning distinction is one of the most common interview questions in this tier: pretraining teaches general language on unlabeled text at huge cost; fine-tuning specializes a pretrained model on your labeled data at modest cost.

---

## 11. Inference

**Inference** is using a trained model to get answers - a forward pass (Concepts 5.1) through the transformer. For a decoder, inference generates one token at a time, feeding each new token back in to produce the next, until it emits a stop signal or hits the context window. Inference is much cheaper than training, but at scale it is still the recurring bill: every user request is tokens in and tokens out, and you pay per token.

Inference on a small transformer can run on CPU (slowly); production inference on large models uses GPUs or hosted APIs. For the BUILD we deliberately stay with a tiny CPU model so inference is instant. Calling a hosted transformer API (the common consulting pattern) needs no local GPU at all - you rent someone else's.

---

## 12. Parameters

**Parameters** are the learned weights and biases (Concepts 5.1), counted across the whole model. "A 7-billion-parameter model" has 7 billion numbers. More parameters generally means more capability but also more memory, more compute, and higher cost to run. As a consultant you match model size to the job: a small model is cheaper and faster and often good enough; a huge model is for hard tasks that justify the cost. Never reach for the biggest model by reflex - size it to the problem and the budget.

---

## Takeaways

- Transformers replaced sequence models by using attention to look at all tokens at once - faster to train, better with long-range context.
- Self-attention makes every token context-aware; positional information restores word order, which attention alone would lose.
- Transformer blocks (attention + feed-forward + stabilizers) stack into deep models; encoder for understanding, decoder for generation, encoder-decoder for translation.
- Tokens (subwords) are the unit of cost and limits; French uses more tokens than English for the same content.
- The context window caps input plus output; long or bilingual documents fill it faster and cost more.
- Pretraining teaches general language on unlabeled text at huge GPU cost (you never do it); fine-tuning specializes a pretrained model on your labeled data at modest GPU cost (you sometimes do it).
- Inference is a forward pass, one token at a time for decoders; parameters are the count of learned weights - size the model to the job.
- Real transformer training, fine-tuning, and large-model inference are GPU work; the BUILD stays tiny and CPU-only to teach the ideas.

---

## References

Authoritative sources used to fact-check this document. Model IDs, context windows, and prices change constantly - verify current values from provider docs before quoting them to a client.

- "Attention Is All You Need" (Vaswani et al., 2017 - the original transformer, self-attention, quadratic cost, transformer block, sinusoidal positional encoding): https://arxiv.org/abs/1706.03762
- The Illustrated Transformer (a widely used plain-language walkthrough): https://jalammar.github.io/illustrated-transformer/
- Hugging Face model-family summary (encoder-only / decoder-only / encoder-decoder, with BERT / GPT / T5 examples): https://huggingface.co/docs/transformers/en/model_summary
- Subword tokenization (BPE, WordPiece, SentencePiece): https://huggingface.co/docs/transformers/en/tokenizer_summary
- Token rule of thumb (~4 characters / ~0.75 words per token, English, approximate): https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them
- Non-English tokenization premium ("Do All Languages Cost the Same?", Petrov et al.): https://arxiv.org/abs/2305.13707
- Claude model IDs, context windows, and pricing (values change - always use current): https://docs.anthropic.com/

Prof. Happy (SUTA Labs)
