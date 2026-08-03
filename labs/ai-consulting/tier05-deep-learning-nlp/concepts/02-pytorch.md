# Concepts 5.2: PyTorch

**Tier 5 - Deep learning and NLP.** Teaching reference. Concepts 5.1 gave you the ideas (neurons, layers, loss, backprop, optimizers). This doc gives you the tool that turns those ideas into running code: **PyTorch**. PyTorch is the most widely used deep learning library, and it is what nearly every AI consulting build and every modern model (including the transformers behind ChatGPT-style tools) is written in.

**Who this is for:** DBAs who finished Concepts 5.1 and Tier 1 Python. No prior PyTorch assumed.

**Run the snippets:** on your **lab server**, as **ec2-user**, start Python:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import torch`. If PyTorch is not installed yet, the BUILD shows the exact CPU-only install command. On this box we always install the **CPU wheel** of PyTorch - there is no GPU.

---

## 1. Tensors: the one data type you must know

A **tensor** is PyTorch's array. It is basically a NumPy array (Tier 2) with two superpowers: it can run on a GPU, and it can automatically track gradients for backprop. If you know NumPy, you know 90% of tensors.

```python
import torch
x = torch.tensor([1.0, 2.0, 3.0])
x
```

Expected output (yours will differ):

```
tensor([1., 2., 3.])
```

Shapes matter. A tensor's **shape** is how many elements it has along each dimension.

```python
m = torch.zeros(2, 3)   # 2 rows, 3 columns, all zeros
m.shape
```

Expected output:

```
torch.Size([2, 3])
```

Common shapes in this tier: a batch of feature vectors is `(batch_size, num_features)`; a batch of class scores is `(batch_size, num_classes)`.

---

## 2. Tensor math is just array math

Tensors add, multiply, and matrix-multiply like you expect. The core operation of every layer is a matrix multiply (`@` or `torch.matmul`) - a batch of weighted sums, done all at once.

```python
a = torch.tensor([[1.0, 2.0], [3.0, 4.0]])
b = torch.tensor([[1.0, 0.0], [0.0, 1.0]])
a @ b
```

Expected output:

```
tensor([[1., 2.],
        [3., 4.]])
```

(`b` is the identity matrix, so `a @ b` returns `a`.)

---

## 3. Autograd: gradients for free

This is the feature that makes PyTorch worth using. Mark a tensor with `requires_grad=True` and PyTorch records every operation you do to it. Call `.backward()` on a result and PyTorch fills in the gradient - the slope from Tier 2 - automatically. No calculus by hand.

```python
w = torch.tensor(3.0, requires_grad=True)
loss = (w - 1) ** 2      # a simple parabola with its minimum at w = 1
loss.backward()          # compute d(loss)/dw
w.grad
```

Expected output:

```
tensor(4.0)
```

The gradient is `4.0`, which is positive, so to lower the loss we move `w` in the negative direction - toward the minimum at 1. That single fact, repeated for millions of weights, is how all deep learning trains.

---

## 4. Model classes: nn.Module

You describe a network by writing a Python class that inherits from `torch.nn.Module`. You define the layers in `__init__` and describe the forward pass in a `forward` method. PyTorch handles backprop for you.

```python
import torch.nn as nn

class TinyNet(nn.Module):
    def __init__(self, num_features, num_classes):
        super().__init__()
        self.hidden = nn.Linear(num_features, 16)   # a fully-connected layer
        self.relu = nn.ReLU()                        # activation
        self.out = nn.Linear(16, num_classes)        # output layer

    def forward(self, x):
        x = self.relu(self.hidden(x))                # forward propagation
        return self.out(x)                           # raw scores (logits)
```

- `nn.Linear(in, out)` is a full layer of neurons: it holds the weights and biases and does the weighted sum for you.
- `forward` is exactly the forward propagation from Concepts 5.1 - data in, prediction out.
- The output is raw scores called **logits**; the loss function turns them into probabilities.

This is the model the BUILD uses.

---

## 5. Loss functions and optimizers, the PyTorch way

PyTorch ships the pieces from Concepts 5.1 ready to use:

```python
model = TinyNet(num_features=10, num_classes=3)
loss_fn = nn.CrossEntropyLoss()                       # classification loss
optimizer = torch.optim.Adam(model.parameters(), lr=0.01)
```

- `nn.CrossEntropyLoss()` is the cross-entropy loss. It even applies softmax internally, so you feed it raw logits.
- `torch.optim.Adam(model.parameters(), lr=...)` is the Adam optimizer wired to every weight and bias in the model, with the learning rate `lr`.

`model.parameters()` hands the optimizer the full list of learnable weights and biases - you never manage them by hand.

---

## 6. The training loop

Every PyTorch training run has the same five-line rhythm inside a loop. This is Concepts 5.1's rhythm in code:

```python
for epoch in range(num_epochs):
    for features, labels in train_loader:     # one batch at a time
        optimizer.zero_grad()                 # 1. clear old gradients
        logits = model(features)              # 2. forward pass (prediction)
        loss = loss_fn(logits, labels)        # 3. how wrong
        loss.backward()                       # 4. backprop -> gradients
        optimizer.step()                      # 5. nudge weights downhill
```

The one line beginners forget is `optimizer.zero_grad()`. PyTorch **accumulates** gradients by default, so if you do not clear them each step, they pile up and training goes haywire. Always zero, forward, loss, backward, step - in that order.

---

## 7. Datasets and DataLoaders: feeding data in batches

You rarely feed a whole dataset at once. PyTorch has two helpers:

- A **Dataset** wraps your data and answers "give me example number i" and "how many examples are there?"
- A **DataLoader** wraps a Dataset and hands out **batches** (Concepts 5.1), optionally shuffled each epoch.

```python
from torch.utils.data import TensorDataset, DataLoader

dataset = TensorDataset(features_tensor, labels_tensor)
loader = DataLoader(dataset, batch_size=16, shuffle=True)
```

`shuffle=True` reorders the data each epoch so the model does not learn the order instead of the pattern. The BUILD uses exactly this.

---

## 8. Train mode vs eval mode

A model behaves differently while training versus while predicting - mainly because of dropout (Concepts 5.1), which is active during training and must be off during prediction.

```python
model.train()   # turn ON dropout etc. - use during the training loop
model.eval()    # turn OFF dropout - use when validating or predicting
```

Also wrap prediction in `torch.no_grad()` so PyTorch does not waste time tracking gradients you will not use:

```python
model.eval()
with torch.no_grad():
    predictions = model(new_features)
```

Forgetting `model.eval()` at prediction time is a classic subtle bug: dropout stays on and your predictions become randomly unstable.

---

## 9. Saving and loading a model

You train once and reuse forever. Save the model's learned parameters (its **state dict** - the weights and biases) to a file, and load them back later.

```python
torch.save(model.state_dict(), "model.pt")          # save

model2 = TinyNet(num_features=10, num_classes=3)     # rebuild same shape
model2.load_state_dict(torch.load("model.pt"))       # load learned weights
model2.eval()
```

Two rules that trip people up:

- Save the `state_dict`, not the whole model object - it is portable and safe.
- To load, you must first create a model with the exact same architecture, then pour the weights in.

One current-version note: as of **PyTorch 2.6**, `torch.load` defaults to `weights_only=True` (a security change - it refuses to unpickle arbitrary Python objects; see: pytorch.org/docs `torch.load`). A plain `state_dict` of tensors loads fine under this default, which is another reason to save the `state_dict` rather than the whole model object - loading a full pickled model can now raise an error unless you explicitly opt out. Stick to `state_dict` and you avoid the problem entirely.

The BUILD saves the trained classifier this way so USE and SURVIVE can reuse it without retraining.

---

## 10. GPU basics (and why we do not use one here)

Moving work to a GPU in PyTorch is almost trivial: pick a device and send the model and data to it.

```python
device = "cuda" if torch.cuda.is_available() else "cpu"
model = model.to(device)
features = features.to(device)
```

On this lab box `torch.cuda.is_available()` is `False`, so `device` is `"cpu"` and everything runs on the processor. That is fine - our models and datasets are tiny and train in seconds.

Where a real project needs a GPU: training a large network on millions of rows, or fine-tuning a transformer with hundreds of millions of parameters. There, the exact same `.to(device)` pattern moves work to `"cuda"` and turns days of CPU time into hours. We flag those spots in the guides. The skill you learn on CPU transfers unchanged.

---

## Takeaways

- A tensor is a NumPy array that can track gradients and run on a GPU. Shapes are `(batch, features)` and `(batch, classes)`.
- Autograd computes gradients automatically via `.backward()` - no calculus by hand.
- Define a model as an `nn.Module` with layers in `__init__` and the forward pass in `forward`.
- The training loop is always: `zero_grad -> forward -> loss -> backward -> step`, over batches from a DataLoader.
- Use `model.train()` while training and `model.eval()` + `torch.no_grad()` while predicting (dropout must be off).
- Save/load with `state_dict`; rebuild the same architecture before loading.
- CPU is enough for tiny models here; a real project moves to a GPU with `.to("cuda")` when scale demands it.

---

## References

Authoritative sources used to fact-check this document, all from the official PyTorch docs. APIs evolve between versions - confirm against the docs for your installed PyTorch version.

- Tensors (creation, shape, math): https://docs.pytorch.org/tutorials/beginner/basics/tensorqs_tutorial.html
- Autograd (`requires_grad`, `.backward()`, `.grad`): https://docs.pytorch.org/tutorials/beginner/basics/autogradqs_tutorial.html
- Building models (`nn.Module`, `nn.Linear`, `nn.ReLU`): https://docs.pytorch.org/tutorials/beginner/basics/buildmodel_tutorial.html
- `nn.CrossEntropyLoss` (expects raw logits; applies log-softmax internally): https://docs.pytorch.org/docs/stable/generated/torch.nn.CrossEntropyLoss.html
- `torch.optim.Adam`: https://docs.pytorch.org/docs/stable/generated/torch.optim.Adam.html
- Optimization loop (gradients accumulate; `zero_grad` each step): https://docs.pytorch.org/tutorials/beginner/basics/optimization_tutorial.html
- Datasets and DataLoaders: https://docs.pytorch.org/docs/stable/data.html
- `torch.load` `weights_only` default (PyTorch 2.6 change): https://docs.pytorch.org/docs/stable/generated/torch.load.html and https://pytorch.org/blog/pytorch2-6/

Prof. Happy (SUTA Labs)
