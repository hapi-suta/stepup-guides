# Interview 01: Fine-Tuning Questions

Five questions you might get in an interview about fine-tuning and transfer learning.

---

## Question 1: When Should You Fine-Tune vs Use Prompt Engineering?

**Question:** Your team wants to classify database alerts. Should you fine-tune a model or use prompt engineering? How do you decide?

**Strong answer:**

**Start with prompt engineering. Only fine-tune if it's not enough.**

The decision hierarchy:
1. **Prompt engineering first** (Module 02): Zero cost, instant iteration. Write a system prompt that describes categories and give a few examples (few-shot). Works for 70% of tasks.

2. **RAG second** (Module 03): If the model needs domain knowledge (your runbooks, documentation), add retrieval. No training needed.

3. **Fine-tuning third** (this module): If prompt engineering gives inconsistent results, wrong formats, or you need sub-second latency.

**Fine-tune when:**
- You need consistent output format every time (always JSON, specific schema)
- Prompt engineering accuracy is stuck below your threshold
- You have 500+ labeled examples
- You need a smaller, faster model (distill knowledge from GPT-4 into DistilBERT)
- Cost: calling GPT-4 1000x/day is expensive; a fine-tuned small model runs locally

**Don't fine-tune when:**
- You have fewer than 100 examples
- The task changes frequently (new categories added often)
- Prompt engineering already works well enough
- You don't have time to maintain the training pipeline

**For database alerts specifically:** Start with zero-shot classification (Module 08 Build 04). If accuracy is below 85%, fine-tune DistilBERT on your labeled alerts. The combination of pre-trained language understanding + your specific alert patterns usually reaches 95%+.

---

## Question 2: Explain LoRA and Why It's Used

**Question:** What is LoRA and why would you use it instead of full fine-tuning?

**Strong answer:**

**LoRA (Low-Rank Adaptation) adds tiny trainable matrices to a frozen model.**

Instead of updating all 110M parameters in BERT, LoRA:
1. Freezes the entire original model
2. Adds two small matrices (A and B) next to each layer
3. Only trains A and B (typically 0.1-1% of original parameters)

**The math:**
```
Original:  output = input @ W           (W is frozen, 768x768)
With LoRA: output = input @ W + input @ A @ B
  A: 768 x 4 = 3,072 trainable params
  B: 4 x 768 = 3,072 trainable params
  Total: 6,144 vs 589,824 (1% of original)
```

**Why use LoRA over full fine-tuning:**
1. **Memory:** Full fine-tuning loads all gradients into GPU memory. LoRA only needs gradients for tiny A and B.
2. **Speed:** Training 6K params is faster than training 590K.
3. **No catastrophic forgetting:** Base model is completely frozen.
4. **Multiple tasks:** Keep one base model, swap different LoRA adapters for different tasks. Like one PostgreSQL install with multiple databases.
5. **Storage:** LoRA adapter files are ~1MB vs ~250MB for full model.

**The rank (r) controls the trade-off:**
- r=1: Minimal capacity, fewest params
- r=4-8: Good default, works for most tasks
- r=16-32: More capacity for complex tasks
- Higher rank = more parameters = more compute but better quality

---

## Question 3: What Is Catastrophic Forgetting?

**Question:** You fine-tuned a language model on database alerts. Now it can't understand basic English sentences. What happened?

**Strong answer:**

**Catastrophic forgetting: the model overwrites its pre-trained knowledge while learning the new task.**

**Why it happens:**
- Pre-trained weights encode general language understanding
- Fine-tuning with a high learning rate makes large updates to these weights
- The new weights are optimized for database alerts but destroyed the general language patterns

**Three fixes:**

1. **Small learning rate (most important):** Use 10x-100x smaller than pre-training lr.
   - Pre-training: lr=0.001
   - Fine-tuning: lr=0.00001
   - The small steps preserve existing knowledge while gently adapting

2. **Freeze early layers:** Early layers learn general features (word meaning, grammar). Later layers learn task-specific features. Freeze the first 8 of 12 BERT layers, train only the last 4.

3. **LoRA:** Completely freeze the base model and train only tiny adapter matrices. Zero risk of forgetting because the original weights never change.

**How to detect it:**
- Test the fine-tuned model on general NLP benchmarks
- Compare embedding quality before and after fine-tuning
- Monitor validation loss on both your task AND a general task during training
- If general task performance drops > 10%, you're forgetting

---

## Question 4: How Do You Prepare Data for Fine-Tuning?

**Question:** You have 10,000 raw database alert messages. Walk me through preparing them for fine-tuning.

**Strong answer:**

**Seven-step pipeline:**

1. **Label the data:** Assign categories to each alert. Options:
   - Manual labeling (most accurate, most time-consuming)
   - Semi-automatic: use zero-shot classification to pre-label, then manually review
   - From existing systems: map PagerDuty severity levels, Jira categories, etc.

2. **Clean the data:**
   - Remove duplicates (exact and near-duplicate)
   - Remove empty or very short texts (< 10 characters)
   - Fix mislabeled examples (check ~5% manually)
   - Standardize format (consistent casing, whitespace)

3. **Check balance:** Equal examples per category. If imbalanced:
   - Undersample majority class
   - Oversample minority class
   - Or use class weights in the loss function

4. **Split the data (BEFORE augmentation):**
   - Train 70%, Validation 15%, Test 15%
   - Stratify by label (same ratio in each split)
   - Hold the test set sacred - never touch during development

5. **Augment (train set only):**
   - Synonym replacement, random deletion, template variation
   - Target: at least 200 examples per category
   - Review augmented examples for correctness

6. **Tokenize:**
   - Use the tokenizer matching your model (BERT tokenizer for BERT)
   - Set appropriate max_length (64 for short alerts, 512 for long texts)
   - Create attention masks for padding

7. **Version and document:**
   - Save with date: `alerts_v2_2024_01_15.jsonl`
   - Document: how many examples, label distribution, augmentation methods
   - Keep test set fixed across experiments for fair comparison

**Key rule:** The quality of your fine-tuned model is 80% determined by data quality. Spend most of your time on steps 1-3.

---

## Question 5: How Do You Evaluate a Fine-Tuned Model?

**Question:** Your fine-tuned model shows 95% accuracy. Is it ready for production?

**Strong answer:**

**Accuracy alone is never enough. You need a complete evaluation.**

**Five things to check:**

1. **Per-class metrics (not just overall accuracy):**
   ```
   Category      Precision  Recall  F1
   performance   0.92       0.95    0.93
   storage       0.88       0.90    0.89
   replication   0.96       0.85    0.90
   security      0.98       0.97    0.97
   ```
   Overall accuracy of 95% could hide that replication recall is only 85% (missing 15% of replication alerts).

2. **Confusion matrix:** Which categories get confused with each other? If storage and performance alerts are frequently confused, you may need more training examples for the boundary cases.

3. **Calibration:** Does the model's confidence match reality? If it says 90% confidence, is it correct 90% of the time? Overconfident models are dangerous in production.

4. **Edge cases:** Test with:
   - Ambiguous alerts (could be multiple categories)
   - Alerts with unusual formatting
   - Very short and very long texts
   - Categories not in training data (should the model say "unknown"?)

5. **Regression testing:** Compare against baseline:
   - vs zero-shot classification (is fine-tuning even better?)
   - vs the previous model version (did the update help?)
   - vs a simple keyword-based classifier (is ML needed at all?)

**Production readiness checklist:**
- F1 > 0.85 on all categories (not just overall)
- Model handles "unknown" categories gracefully
- Latency meets requirements (< 100ms for real-time alerts)
- Model is versioned and reproducible
- Monitoring in place to detect model drift
