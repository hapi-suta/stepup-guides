# Interview: Tier 5 - Deep Learning and NLP

**Tier 5 interview prep.** These are the questions an AI-consulting client, a hiring panel, or a skeptical CTO will actually ask to check whether you understand deep learning and NLP well enough to be trusted with their text and their money. Each entry has the question, a model answer in plain language, and "why they ask" so you know what they are really probing.

The skill being tested across all of these is the same as every tier: can you explain something technical simply and honestly to someone who does not do it? For deep learning that is doubly important, because the field is full of hype and the consultant's job is to cut through it.

---

## 1. What is attention, in plain language?

**Model answer.** Attention is how a modern language model decides which other words to look at when it is trying to understand one word. Take the sentence "The invoice was paid because it was overdue." To understand what "it" refers to, the model looks back at all the other words and figures out that "it" means "the invoice", not "paid". Attention gives every other word a weight - high for the words that matter right now, low for the ones that do not - and blends in the important ones. It is a smart, context-sensitive lookup: for each word, "which other words should I pay attention to?" That single mechanism, repeated across every word and stacked in layers, is what lets transformers understand context and is the core of every model like ChatGPT or Claude.

**Why they ask.** Attention is THE idea behind modern AI. They want to see you can explain the engine of the whole field without hiding behind jargon or math - because if you can explain it to them, you can explain it to their executives.

---

## 2. What is the difference between pretraining and fine-tuning?

**Model answer.** Pretraining is the first, enormous phase where a model learns language in general from a giant pile of raw text - just predicting the next word over and over. No human labels are needed because the text is its own answer key. This is where the model absorbs grammar, facts, and multiple languages, and it costs millions of dollars and thousands of GPUs, so nobody but the big labs does it. Fine-tuning takes that already-pretrained model and trains it a little more on YOUR specific labeled data so it specializes - your document types, your tone, your domain. Fine-tuning needs far less data and compute, hours instead of weeks. The short version: pretraining teaches general language at huge cost and you never do it; fine-tuning specializes a pretrained model on your data at modest cost, and you sometimes do it. As a consultant I almost always start with a pretrained model and either fine-tune it or just prompt it.

**Why they ask.** Clients constantly ask "should we train our own model?" The right answer is almost always no - use a pretrained one and fine-tune or prompt it. They want to know you will not burn their budget pretraining from scratch when a fine-tune or a good prompt would do.

---

## 3. What is a context window and why does it matter?

**Model answer.** The context window is the maximum amount of text - measured in tokens, not words - that a model can consider at one time, counting both what you send in and what it writes back. If a model has an 8,000-token window and you feed it a 7,500-token document, only 500 tokens are left for its answer. Feed it something bigger than the window and it simply will not fit - you have to split the document into chunks and process them piece by piece. It matters for three practical reasons: long documents must be chunked, bigger context costs more money and runs slower, and different languages use different numbers of tokens for the same content. So when a client asks "can it read our 200-page contract at once?", the honest answer starts with "how many tokens is that, and what is the model's window?"

**Why they ask.** The context window drives cost, architecture (do you need chunking and retrieval?), and feasibility. They want to see you reason in tokens and windows, because that is what determines whether a proposed solution is even possible and what it will cost.

---

## 4. How would you handle a bilingual English/French NLP problem?

**Model answer.** First, I would not build two separate systems if I can avoid it. The cleaner approach is one pipeline that handles both languages. Concretely: I clean and normalize text the same way for both, I supply stop-word lists for BOTH English and French so I strip noise words in each, and I use a feature representation or model that can hold both languages at once - for a classic approach, one shared TF-IDF vocabulary that contains English and French words; for a modern approach, a multilingual pretrained model like multilingual BERT that already understands both. I would make sure my training data has enough examples in each language, because a model trained mostly on English will quietly underperform on French. Two gotchas I would call out: French text usually costs more tokens than the same English content, so budget for that; and I must apply the exact same cleaning and tokenization at inference as at training, or accuracy silently collapses. If the two languages genuinely behave very differently for the task, I would measure per-language accuracy separately so a good English score does not hide a bad French one.

**Why they ask.** Bilingual and multilingual requirements are extremely common in real consulting (Canada, Europe, global companies). They want to see you think about balanced data, shared representations, per-language evaluation, and the token-cost and tokenization traps - not just "throw it all in and hope."

---

## 5. Your model gets 100% accuracy on the training data. Are you happy?

**Model answer.** No - that is a warning sign, not a victory. A model that is perfect on the data it trained on has very likely memorized it, including the noise, rather than learning the general pattern. That is overfitting. The only number that matters is accuracy on data the model has NEVER seen - a held-out validation or test set. If it is great on training data but much worse on held-out data, I fix it with the standard tools: dropout, weight decay, a smaller model, more data, and early stopping. I never report a training-set score to a client as if it were real performance; I always report held-out results, and ideally on fresh data collected after the model was built.

**Why they ask.** Reporting training accuracy as if it were real accuracy is one of the most common and most damaging mistakes in the field. They want to confirm you will measure honestly on unseen data and recognize overfitting instead of celebrating it.

---

## 6. A client wants you to train a model from scratch for their chatbot. What do you tell them?

**Model answer.** I would gently talk them out of it in almost every case. Training a capable language model from scratch means pretraining, which costs millions of dollars, thousands of GPUs, and months, plus a data and MLOps team - it only makes sense for a handful of large labs. What they actually want is the behavior, and I can get that far faster and cheaper three ways, in order of effort: first, just prompt a strong pretrained model well (often enough); second, add retrieval so the model answers from their own documents (RAG); third, fine-tune a pretrained model on their examples if prompting and retrieval are not enough. Each of these reuses the enormous, already-paid-for pretraining and specializes only the last mile. I would only consider anything closer to from-scratch if they had a truly unique domain, massive proprietary data, and a budget to match - and even then I would start with fine-tuning. My job is to get them the outcome, not the most expensive path to it.

**Why they ask.** This separates consultants who chase shiny, expensive projects from ones who protect the client's budget. They want to hear the ladder - prompt, then retrieve, then fine-tune, and only then consider training - because picking the cheapest rung that works is the whole value of hiring you.

---

## 7. What is the learning rate, and how do you know it is wrong?

**Model answer.** The learning rate is the size of the step the model takes each time it adjusts its weights during training - how far it moves downhill on the error each step. You diagnose it by watching the loss over epochs. If the loss shoots UP and blows to infinity or "not a number", the learning rate is too high - the steps overshoot and the gradients explode; you lower it and can add gradient clipping as a safety net. If the loss barely moves - inching down or staying flat for many epochs - the learning rate is too low and training is stalling; you raise it. When it is right, the loss falls smoothly every epoch and settles. It is the single most common knob to get wrong, so it is the first thing I check when a training run misbehaves.

**Why they ask.** "The training just doesn't work" is a daily reality, and a bad learning rate is the top cause. They want to see you can read a loss curve and immediately know which way to turn the knob - that is hands-on competence, not just theory.

---

## 8. Why do we need a validation set separate from the training set?

**Model answer.** Because a model will always look good on the data it learned from - that tells you nothing about how it does on new data, which is all that matters in production. The validation set is data the model never trains on, so it is an honest preview of real-world performance. I use it two ways: to detect overfitting (when training loss keeps falling but validation loss starts rising, I stop), and to choose settings like model size and when to stop training. The golden rule is to never let the model learn from the validation set, or it stops being honest. In serious work I keep a third, final test set that I touch only once at the very end, so even my tuning choices do not leak into the number I report to the client.

**Why they ask.** Data leakage between training and evaluation is how "amazing" models turn out to be worthless in production. They want to confirm you understand held-out evaluation cold, because every trustworthy result you ever report depends on it.

---

## 9. What are tokens, and why should a client care about them?

**Model answer.** A token is the unit of text a language model actually reads - usually a piece of a word. As a rough rule, one token is about three-quarters of an English word, so a thousand-word document is roughly thirteen hundred tokens. Clients should care for one blunt reason: tokens are the unit of both cost and limits. You pay per token in and per token out, and the model's context window is measured in tokens, not pages. Two things surprise people: long documents can blow past the window and have to be chunked, and other languages - French, for example - often use more tokens than English for the same meaning, so a bilingual project's French half costs more. When I estimate the price or feasibility of an AI feature, I estimate it in tokens, because that is what actually drives the bill.

**Why they ask.** Token math is how you forecast cost and check feasibility, and it is invisible to clients until the invoice arrives. They want to see you can translate "process our documents" into a token-and-dollar estimate - a core consulting deliverable.

---

## 10. When would you use a simple TF-IDF classifier instead of a big transformer?

**Model answer.** More often than people expect. If the task is "what type of document is this?" or "is this review positive or negative?", and the answer is driven by which words appear rather than by subtle word order, a TF-IDF classifier is fast, cheap, runs on a plain CPU, is easy to explain, and is often just as accurate. I reach for a transformer when meaning genuinely depends on order and long-range context - "the movie was not good" versus "good" - or when I need multilingual understanding beyond keyword overlap, or when accuracy on hard cases justifies the extra cost and the GPU. My default is to start simple, measure, and only move up to a transformer if the numbers say I need to. Starting with the biggest model by reflex wastes money and makes the system harder to run and explain.

**Why they ask.** The industry over-reaches for large models. They want to see you match the tool to the job and the budget - knowing when the cheap, simple, CPU-friendly option is the RIGHT engineering choice is exactly the judgment that makes a consultant worth paying.

---

## How to use this

Do not memorize these word for word. Read the model answer, then close the doc
and say it out loud in your own words to an imaginary non-technical executive. If
you can explain attention, the pretraining/fine-tuning split, context windows,
tokens, and honest evaluation to someone who does not do AI - simply, and without
overselling - you will pass any Tier 5 conversation, technical or business.

Prof. Happy (SUTA Labs)
