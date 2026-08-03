# Interview 01: Neural Network Questions

Five questions you might get in an interview about neural networks and deep learning.

---

## Question 1: Explain How a Neural Network Learns

**Question:** Walk me through what happens during one training step of a neural network.

**Strong answer:**

**One training step has 4 parts:**

1. **Forward pass:** Data flows through the network layer by layer.
   - Each layer computes: `output = activation(input @ weights + bias)`
   - The final layer produces a prediction (e.g., 0.73 probability of incident)

2. **Loss calculation:** Compare prediction to the actual answer.
   - Classification: BCELoss or CrossEntropyLoss
   - Regression: MSELoss
   - The loss is one number: "how wrong was the model?"

3. **Backward pass (backpropagation):** Calculate how much each weight contributed to the error.
   - PyTorch traces back through every operation (autograd)
   - Each weight gets a gradient: "if I increase this weight, how does the loss change?"
   - Gradients are calculated using the chain rule from calculus

4. **Weight update:** Adjust weights to reduce the error.
   - `new_weight = old_weight - learning_rate * gradient`
   - The optimizer (Adam, SGD) handles this
   - Adam adapts the learning rate per-parameter

**Key insight:** The network doesn't "understand" anything. It just adjusts millions of numbers (weights) to minimize a loss function. Given enough data and the right architecture, this process discovers useful patterns.

---

## Question 2: What Is Overfitting and How Do You Prevent It?

**Question:** Your neural network has 99% training accuracy but 75% test accuracy. Diagnose and fix.

**Strong answer:**

**Diagnosis:** Overfitting. The model memorized training data instead of learning general patterns.

**Five prevention techniques:**

1. **Dropout (nn.Dropout(0.2-0.5)):** Randomly disables neurons during training. Forces the network to not rely on any single neuron. Most common technique.

2. **Early stopping:** Monitor validation loss each epoch. Stop training when it stops improving. Save the best weights and restore them.

3. **More data:** The simplest fix. More training examples = harder to memorize.

4. **Simpler model:** Fewer layers, fewer neurons per layer. A model with 73 parameters can't memorize 1000 examples.

5. **Regularization (weight decay):** Penalizes large weights. `optimizer = Adam(params, lr=0.001, weight_decay=1e-4)`

**How to detect it:**
- Plot training loss and validation loss per epoch
- If training loss keeps decreasing but validation loss starts increasing, you're overfitting
- The gap between train and test accuracy > 5% is a warning sign

---

## Question 3: When Would You Use a Neural Network vs Classical ML?

**Question:** Your team debates using a neural network for a new project. When is it the right choice?

**Strong answer:**

**Use classical ML (Random Forest, XGBoost) when:**
- Tabular/structured data (database rows and columns)
- Small dataset (< 10,000 rows)
- Need interpretability (explain WHY the model predicted something)
- Need fast training (minutes, not hours)
- Limited compute (no GPU)

**Use neural networks when:**
- Unstructured data (text, images, audio)
- Large dataset (> 100,000 rows)
- Complex patterns that linear models can't capture
- You have GPU access
- State-of-the-art accuracy matters more than interpretability

**For a DBA monitoring system:**
- Start with Random Forest (it's fast, interpretable, and works well on tabular data)
- Only switch to neural network if Random Forest accuracy is insufficient
- Gradient boosting (XGBoost/LightGBM) usually beats neural networks on tabular data

**The trap:** Beginners often reach for neural networks first because they're trendy. But a well-tuned XGBoost model with good features usually outperforms a neural network on structured data.

---

## Question 4: Explain Activation Functions

**Question:** Why do neural networks need activation functions? What happens without them?

**Strong answer:**

**Without activation functions, stacking layers does nothing.**

Two linear layers: `z = (x @ W1 + b1) @ W2 + b2` simplifies to `z = x @ W_combined + b_combined`. It's mathematically equivalent to one layer.

Activation functions add non-linearity - the ability to learn curves, not just straight lines.

**Common activation functions:**

| Function | Range | Use | Why |
|----------|-------|-----|-----|
| ReLU | 0 to infinity | Hidden layers | Simple, fast, no vanishing gradient |
| Sigmoid | 0 to 1 | Binary output | Probability interpretation |
| Softmax | 0 to 1 (sum=1) | Multi-class output | Probability distribution |
| GELU | smooth curve | Transformer hidden layers | Used in BERT, GPT |

**Practical rules:**
- Hidden layers: always ReLU (or GELU for transformers)
- Binary output: Sigmoid
- Multi-class output: nothing (CrossEntropyLoss includes Softmax)
- Never use Sigmoid in hidden layers (causes vanishing gradients)

---

## Question 5: Your Model's Loss Goes to NaN. Debug It.

**Question:** During training, the loss suddenly becomes NaN at epoch 15. What happened and how do you fix it?

**Strong answer:**

**Debugging checklist (in order):**

1. **Learning rate too high:**
   - Most common cause. Gradients explode, weights become infinity, loss becomes NaN.
   - Fix: reduce learning rate by 10x (0.01 -> 0.001)
   - Test: if it NaNs at epoch 1, definitely learning rate

2. **Gradient explosion:**
   - Weights grow exponentially. Related to learning rate but also to architecture.
   - Fix: add gradient clipping
   - `torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)`

3. **Bad data:**
   - NaN or infinity values in input data
   - Fix: `assert not torch.isnan(X).any()` before training
   - Check for division by zero in normalization (std=0 for constant features)

4. **Wrong loss function:**
   - BCELoss with predictions outside 0-1 range (forgot Sigmoid)
   - log(0) = -infinity in cross-entropy
   - Fix: use BCEWithLogitsLoss (includes sigmoid, numerically stable)

5. **Numerical instability:**
   - Very large or very small numbers in intermediate computations
   - Fix: normalize inputs, use batch normalization, use mixed precision carefully

**Debugging approach:**
```python
# Add these checks during training:
for name, param in model.named_parameters():
    if torch.isnan(param.grad).any():
        print(f"NaN gradient in {name} at epoch {epoch}")
    if param.grad.abs().max() > 1000:
        print(f"Exploding gradient in {name}: {param.grad.abs().max()}")
```

**Prevention:** Use Adam optimizer (handles learning rate adaptation), gradient clipping, and batch normalization. These three together prevent most NaN issues.
