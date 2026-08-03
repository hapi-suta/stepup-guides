# Fine-Tuning - Concepts

Fine-tuning takes a pre-trained model (like BERT or GPT) and teaches it your specific task using your data. Instead of training from scratch (which costs millions of dollars), you start with a model that already understands language and nudge it toward your domain.

---

## Why Should You Care?

Pre-trained models are general purpose. They know English, code, and common knowledge. But they don't know:
- Your specific alert patterns and severity levels
- Your PostgreSQL naming conventions
- Your team's incident categories
- Your company's database terminology

Fine-tuning bridges that gap. You take a model that "speaks English" and teach it to "speak DBA."

---

## The DBA Analogy

| Database Concept | Fine-Tuning Equivalent |
|-----------------|----------------------|
| Template database (template1) | Pre-trained model (BERT, GPT) |
| CREATE DATABASE mydb TEMPLATE template1 | Fine-tune model on your data |
| The template has base schemas/extensions | The pre-trained model has general language knowledge |
| Your DB adds custom tables, functions, data | Your fine-tuned model adds domain-specific knowledge |
| You don't rebuild PostgreSQL from source | You don't retrain the entire model from scratch |

Key insight: **Just like you create a database from a template instead of building PostgreSQL from source, you fine-tune from a pre-trained model instead of training from scratch.**

---

## Types of Fine-Tuning

### 1. Full Fine-Tuning
Update ALL model parameters using your data.

- **Pros:** Best quality, model fully adapts
- **Cons:** Expensive, needs lots of data, risk of catastrophic forgetting (model forgets what it knew)
- **When:** You have a lot of data (10,000+ examples) and compute (GPU)

### 2. LoRA (Low-Rank Adaptation)
Freeze the original model. Add small trainable layers on top.

- **Pros:** Fast, cheap, low memory, original model stays intact
- **Cons:** Slightly lower quality than full fine-tuning
- **When:** Limited compute, want to experiment quickly, most practical choice

### 3. Prompt Tuning / Prefix Tuning
Learn a set of "soft prompts" (learnable vectors) that are prepended to the input. The model itself is completely frozen.

- **Pros:** Extremely cheap, model completely unchanged
- **Cons:** Limited capacity, not as powerful
- **When:** Very limited compute, simple tasks

### 4. API-based Fine-Tuning
Send your data to an API (OpenAI, Anthropic) and they fine-tune for you.

- **Pros:** No GPU needed, no code to write
- **Cons:** Cost per training run, data leaves your environment, limited control
- **When:** Using cloud APIs and want a quick improvement

---

## When to Fine-Tune vs Not

**DON'T fine-tune when:**
- Prompt engineering solves your problem (try this first - Module 02)
- RAG can provide the needed context (try this second - Module 03)
- You have fewer than 100 training examples
- The task is general (summarization, translation, basic Q&A)

**DO fine-tune when:**
- You need consistent output format (always return JSON, always use specific terminology)
- You need domain-specific knowledge that prompts can't capture
- You need lower latency (fine-tuned smaller model vs prompting a larger model)
- You have 500+ labeled examples for your specific task
- Prompt engineering and RAG have been tried and aren't sufficient

**The hierarchy:**
1. First: Prompt engineering (free, instant)
2. Second: RAG (moderate effort, no training)
3. Third: Fine-tuning (requires data and compute)
4. Last resort: Train from scratch (requires massive data and compute)

---

## What You Need for Fine-Tuning

1. **A pre-trained model:** BERT, DistilBERT, GPT-2, or any HuggingFace model
2. **Labeled training data:** Input-output pairs for your task
   - Classification: (text, label) pairs - at least 500
   - Generation: (prompt, completion) pairs - at least 200
3. **Compute:** GPU recommended but small models work on CPU
4. **A clear task:** Classification, NER, summarization, generation, etc.

---

## What You'll Build

| Build | What | Why |
|-------|------|-----|
| 01 - Fine-Tuning Concepts in Code | Transfer learning, frozen vs unfrozen layers | Understand what fine-tuning actually changes |
| 02 - Fine-Tune BERT for Classification | Classify database alerts using BERT | Most common fine-tuning task |
| 03 - LoRA: Efficient Fine-Tuning | Fine-tune with tiny parameter count | Practical technique used in production |
| 04 - Preparing Training Data | Data formatting, splits, augmentation | The quality of your data determines your results |
