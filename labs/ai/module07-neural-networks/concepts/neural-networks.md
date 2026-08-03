# Concepts: Neural Networks

## What Is a Neural Network?

A neural network is layers of math stacked on top of each other. Each layer takes numbers in, multiplies by weights, adds a bias, and passes the result through an activation function. That's it.

You already built one in Module 05 (Build 04, Step 5). That was a single-layer network. This module adds more layers and uses PyTorch instead of raw NumPy.

## Why "Neural"?

The name comes from brain neurons, but don't take the analogy too far. A neural network is just:

```
input -> multiply by weights -> add bias -> activation function -> output
```

Stack multiple layers of this and you get a "deep" neural network (that's what "deep learning" means - multiple layers).

## The DBA Analogy

Think of a neural network like a multi-stage query pipeline:

```sql
-- Stage 1: Raw data comes in
SELECT cpu, memory, connections FROM server_metrics;

-- Stage 2: Create derived features (like a hidden layer)
SELECT
    cpu * 0.4 + memory * 0.2 AS resource_score,
    connections * 0.3 + cpu * 0.1 AS load_score
FROM stage_1;

-- Stage 3: Final prediction (like the output layer)
SELECT
    CASE WHEN resource_score * 0.7 + load_score * 0.3 > 0.5
         THEN 'incident' ELSE 'healthy' END
FROM stage_2;
```

Each stage transforms the data. The "weights" (0.4, 0.2, 0.3, etc.) are learned automatically during training.

## Why PyTorch?

In Module 05, you wrote gradient descent by hand in NumPy. That works for simple problems but breaks down with:
- Many layers (gradient calculation gets complicated)
- Large data (NumPy is CPU-only, PyTorch uses GPU)
- Complex architectures (attention, convolutions, etc.)

PyTorch handles all of this:
- **Automatic differentiation:** calculates gradients for you (no manual math)
- **GPU acceleration:** same code runs on CPU or GPU
- **Building blocks:** pre-built layers, loss functions, optimizers
- **Ecosystem:** used by Meta, Tesla, OpenAI for production models

## Key Concepts

### Tensors
PyTorch's version of NumPy arrays. Same idea (multi-dimensional arrays of numbers), but with GPU support and automatic gradient tracking.

### Layers
- **Linear layer:** `output = input @ weights + bias` (same as Module 05)
- **Activation function:** Introduces non-linearity (ReLU, sigmoid, etc.)
- **Dropout:** Randomly turns off neurons during training (prevents overfitting)

### Training Loop
Same pattern as Module 05, but using PyTorch:
1. Forward pass: run data through the network
2. Calculate loss: how wrong are the predictions?
3. Backward pass: calculate gradients (PyTorch does this automatically)
4. Update weights: optimizer adjusts weights using gradients

### Activation Functions
Without activation functions, stacking layers does nothing (it's still just one linear transformation). Activation functions add non-linearity - the ability to learn curves, not just straight lines.

| Function | Output Range | Use Case |
|----------|-------------|----------|
| ReLU | 0 to infinity | Hidden layers (most common) |
| Sigmoid | 0 to 1 | Binary classification output |
| Softmax | 0 to 1 (sums to 1) | Multi-class classification output |

## What You'll Build

| Build | Topic | What You'll Learn |
|-------|-------|-------------------|
| 01 | PyTorch Basics | Tensors, autograd, basic operations |
| 02 | Your First Neural Network | Build, train, and evaluate a 3-layer network |
| 03 | Training Techniques | Batch training, learning rate, dropout, saving models |
| 04 | Practical Neural Network | End-to-end project: predict server incidents |
