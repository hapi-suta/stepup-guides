# USE 01: Neural Network Exercises

Practice what you built. Each exercise reinforces a concept from Builds 01-04.

---

## Exercise 1: Tensor Operations (Build 01)

Get comfortable with PyTorch tensors.

**Task:**
1. Create a tensor of 10 random server CPU readings (between 0 and 100)
2. Normalize them to 0-1 range using min-max normalization
3. Calculate the mean and standard deviation
4. Create a second tensor of 10 memory readings
5. Stack them into a (10, 2) matrix using `torch.stack()` or `torch.column_stack()`
6. Compute the dot product between the CPU and memory vectors

**Hint:** `torch.rand(10) * 100` creates random numbers between 0 and 100.

---

## Exercise 2: Autograd Exploration (Build 01)

Understand how PyTorch tracks gradients.

**Task:**
1. Create two tensors with `requires_grad=True`: weight and bias
2. Compute: `prediction = input * weight + bias` for inputs [1, 2, 3, 4, 5]
3. Compute MSE loss against targets [3, 5, 7, 9, 11]
4. Call `loss.backward()`
5. Print the gradients for both weight and bias
6. Manually verify the bias gradient: it should be `2 * mean(predictions - targets)`

---

## Exercise 3: Build a Regression Network (Build 02)

Build a neural network that predicts query execution time (regression, not classification).

**Setup:**
```python
import torch
import numpy as np
np.random.seed(42)
n = 500
cpu = np.random.uniform(0, 1, n).astype(np.float32)
table_size = np.random.uniform(0, 1, n).astype(np.float32)
index_count = np.random.uniform(0, 1, n).astype(np.float32)
query_time = (30 * cpu + 50 * table_size - 20 * index_count + np.random.normal(0, 3, n)).astype(np.float32)
```

**Changes from classification:**
- Output layer: `nn.Linear(hidden, 1)` with NO sigmoid (raw number output)
- Loss function: `nn.MSELoss()` instead of BCELoss
- Evaluation: R2 score or RMSE instead of accuracy

**Task:** Train the model and report the RMSE on the test set. Target: RMSE < 5.

---

## Exercise 4: Dropout Experiment (Build 03)

Prove that dropout reduces overfitting.

**Task:**
1. Create a SMALL dataset (100 samples, 5 features)
2. Build a LARGE model (3 hidden layers, 64 neurons each)
3. Train without dropout for 200 epochs - record train and test accuracy
4. Train with dropout (0.3) for 200 epochs - record train and test accuracy
5. Print a comparison table showing the train/test gap for each model

**Expected outcome:** The model without dropout overfits (train >> test). The dropout model has a smaller gap.

---

## Exercise 5: Complete Project - Multi-class Classifier (Build 04)

Build a network that classifies servers into 3 categories: healthy, warning, critical.

**Setup:**
```python
# Label: 0=healthy, 1=warning, 2=critical
# Use nn.CrossEntropyLoss() for multi-class
# Output layer: nn.Linear(hidden, 3)  # 3 classes
# No sigmoid - CrossEntropyLoss applies softmax internally
```

**Task:**
1. Generate 1000 servers with 5 features
2. Label them: healthy (CPU<60), warning (60<CPU<85), critical (CPU>85 or connections>250)
3. Split, normalize, create DataLoader
4. Build a model with dropout and 3 output neurons
5. Train with early stopping
6. Print a classification report with all 3 classes
7. Save the model with scaler parameters

**Hint:** `y` should contain integers (0, 1, 2), not floats. Use `torch.tensor(y, dtype=torch.long)`.

---

## Scoring Guide

| Exercise | Skill Tested | Difficulty |
|----------|-------------|------------|
| 1 | Tensor creation and manipulation | Beginner |
| 2 | Autograd understanding | Beginner |
| 3 | Regression (not just classification) | Intermediate |
| 4 | Overfitting diagnosis and dropout | Intermediate |
| 5 | Multi-class with full pipeline | Advanced |
