# USE 01: Fine-Tuning Exercises

Practice what you built. Each exercise reinforces a concept from Builds 01-04.

---

## Exercise 1: Freeze Strategy Comparison (Build 01)

Compare three freezing strategies on the same model.

**Task:**
1. Create a 4-layer neural network for binary classification (reuse Module 07 data)
2. Pre-train it for 100 epochs
3. Fine-tune with three strategies:
   - Strategy A: Freeze all layers, train only the last layer
   - Strategy B: Freeze first 2 layers, train last 2
   - Strategy C: Full fine-tuning (train everything with small lr)
4. Print a comparison table showing accuracy and training time for each

**Expected outcome:** Strategy B should be the best balance of accuracy and speed.

---

## Exercise 2: Build an Alert Classifier (Build 02)

Build a complete alert classification pipeline from scratch.

**Task:**
1. Write 15 alert messages per category for: `cpu`, `memory`, `disk`, `network` (60 total)
2. Tokenize using DistilBERT tokenizer
3. Fine-tune with frozen backbone + classification head
4. Print per-category accuracy on the test set
5. Test with 5 completely new alerts you write after training

**Hint:** Use `AutoModel.from_pretrained("distilbert-base-uncased")` for the backbone.

---

## Exercise 3: LoRA Rank Comparison (Build 03)

Test how LoRA rank affects accuracy and parameter count.

**Task:**
1. Create a simple classification task (500 samples, 10 features, 3 classes)
2. Build a pre-trained model (3 layers, 64 neurons each)
3. Fine-tune with LoRA at ranks: 1, 2, 4, 8, 16
4. For each rank, print: trainable params, final accuracy, training time
5. Plot or print a table showing the trade-off

**Expected outcome:** Rank 4-8 should give the best accuracy-to-parameter ratio.

---

## Exercise 4: Data Quality Audit (Build 04)

Audit a messy dataset and clean it.

**Task:**
1. Create a deliberately messy dataset (100 examples) with:
   - 5 empty texts
   - 10 duplicate texts
   - 5 mislabeled examples (wrong category)
   - Imbalanced classes (40 vs 10 vs 10 vs 40)
2. Write a `audit_dataset()` function that detects all issues
3. Write a `clean_dataset()` function that fixes them (except mislabels - flag for review)
4. Print before/after statistics
5. Show which examples were flagged as potentially mislabeled (use zero-shot classification to detect)

**Hint:** Use `pipeline("zero-shot-classification")` to detect mislabels automatically.

---

## Exercise 5: End-to-End Fine-Tuning Pipeline (All Builds)

Build a complete fine-tuning pipeline for incident severity classification.

**Task:**
1. Generate 200 alert messages across 3 severity levels: `low`, `medium`, `critical`
2. Run data quality checks (Build 04)
3. Augment to at least 300 examples (Build 04)
4. Tokenize with DistilBERT (Build 02)
5. Fine-tune with frozen backbone + LoRA on the classification head (Build 03)
6. Implement early stopping on validation loss
7. Print classification report with precision, recall, F1 per severity
8. Save the model and test with 5 new alerts

**Target:** F1 > 0.75 on all three severity levels.

---

## Scoring Guide

| Exercise | Skill Tested | Difficulty |
|----------|-------------|------------|
| 1 | Freezing strategies and transfer learning | Beginner |
| 2 | End-to-end BERT fine-tuning | Intermediate |
| 3 | LoRA configuration and trade-offs | Intermediate |
| 4 | Data quality and cleaning | Intermediate |
| 5 | Complete fine-tuning pipeline | Advanced |
