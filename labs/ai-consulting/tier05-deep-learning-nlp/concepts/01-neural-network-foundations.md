# Concepts 5.1: Neural Network Foundations

**Tier 5 - Deep learning and NLP.** Teaching reference. This is the tier where models stop being lines and curves and start being **networks**. The good news: a neural network is not a new idea. It is the same "measure how wrong you are, then step downhill to improve" loop from Tier 2, wired up in layers. If you understood gradient descent and loss, you already understand the engine. This doc gives you the vocabulary and the mental pictures so the PyTorch code in the BUILD makes sense.

**Who this is for:** DBAs. We assume you finished Tier 2 (gradient descent, loss, learning rate) and Tier 1 (Python). No prior deep learning assumed.

**No code to run here** - this is the concepts reference. The BUILD is where you run things. Read this first.

---

## 1. The neuron: a weighted sum plus a decision

A single **neuron** (also called a unit) is tiny. It does three things:

1. Takes some input numbers.
2. Multiplies each input by a **weight** and adds them all up (a weighted sum - the dot product from Tier 2).
3. Adds one more number called a **bias**, then passes the result through an **activation function** that decides how strongly the neuron "fires."

In plain arithmetic, one neuron computes:

```
output = activation( (input1 * weight1) + (input2 * weight2) + ... + bias )
```

That is it. A neuron is a weighted vote followed by a yes/no-ish squash. The weights say how much each input matters. The bias shifts the decision line so the neuron can fire more or less easily.

Picture a loan-approval neuron. Inputs: income, credit score, debt. It learns big positive weights on income and credit score, a negative weight on debt, and a bias that sets the approval threshold. That single neuron is basically the logistic regression you may have seen. A neural network is many of these stacked and connected.

---

## 2. Weights and biases: the things that get learned

Everything a neural network "knows" lives in its **weights** and **biases**. They are just numbers. Training is nothing more than nudging these numbers until the network's outputs match the right answers.

- A **weight** scales one input on the way into a neuron. Big weight = that input matters a lot. Near-zero weight = the network learned to ignore it.
- A **bias** is a per-neuron offset added after the weighted sum. It lets a neuron shift its threshold up or down independent of the inputs.

When people say a model "has 7 billion parameters," the parameters are the weights and biases. More parameters means more capacity to learn patterns - and more data and compute needed to train them.

---

## 3. Layers: neurons working in parallel, then in sequence

One neuron is weak. The power comes from arranging many.

- A **layer** is a group of neurons that all read the same inputs at the same time.
- The **input layer** is just your raw features (for text, it will be numbers derived from words).
- **Hidden layers** sit in the middle. They transform the data into more useful internal representations. "Deep" learning simply means more than one hidden layer.
- The **output layer** produces the final answer - for example one number per class (spam vs not spam, or English-doc-type A vs B vs C).

Data flows input layer -> hidden layer(s) -> output layer. Each layer's outputs become the next layer's inputs. Early layers learn simple patterns; later layers combine them into complex ones.

---

## 4. Activation functions: the source of the power

If every neuron only did a weighted sum, stacking layers would be pointless - a stack of straight-line operations collapses back into one straight line. The **activation function** is the nonlinear squash that breaks that collapse and lets the network bend to fit complicated data.

Three you will meet:

- **ReLU** (Rectified Linear Unit): `max(0, x)`. If the input is negative, output 0; otherwise pass it through. Cheap, simple, and the default for hidden layers. This is what our BUILD uses.
- **Sigmoid**: squashes any number into the range 0 to 1. Good for a single yes/no probability.
- **Softmax**: turns a row of raw output numbers into probabilities that add up to 1. Perfect for "which of these N classes is it?" - exactly the document classifier in the BUILD.

Rule of thumb: ReLU in the hidden layers, softmax at the output for multi-class classification.

---

## 5. Forward propagation: making a prediction

**Forward propagation** (or "forward pass") is just running data through the network from input to output to get a prediction. Multiply by weights, add biases, apply activations, layer by layer, until you reach the output. No learning happens on a forward pass - it is pure prediction. When you later use the trained classifier on a new document, that is a forward pass.

---

## 6. Loss: measuring how wrong the prediction is

A **loss function** turns "how wrong was that prediction?" into a single number. Smaller loss = better. This is the same idea as MSE from Tier 2, but for classification we use a different loss:

- **Cross-entropy loss** is the standard for classification. It is large when the network is confidently wrong, and small when it is confidently right. It punishes a model that says "95% sure it is class A" when the truth was class B.

The loss is the thing training tries to shrink. It is the height of the valley from the Tier 2 fog-walking picture - we want the bottom.

---

## 7. Backpropagation: figuring out which knob to turn

We have a loss. Now, which of the thousands of weights should go up, and which down, to reduce it? **Backpropagation** ("backprop") answers that. It uses calculus (the chain rule) to compute, for every single weight and bias, how much that parameter contributed to the loss - its **gradient**. The gradient is the slope from Tier 2, one per parameter.

You do not compute backprop by hand. PyTorch does it automatically: you call `loss.backward()` and every parameter gets its gradient filled in. That one line is why frameworks exist.

The full training rhythm is:

1. Forward pass -> prediction.
2. Compute loss -> how wrong.
3. Backprop -> gradient for every parameter.
4. Optimizer step -> nudge every parameter downhill.
5. Repeat.

---

## 8. Optimizers: how the step downhill is taken

The **optimizer** is the rule for turning gradients into actual updates. Plain gradient descent (Tier 2) subtracts `learning_rate * gradient` from each weight. Real training usually uses a smarter version:

- **SGD** (Stochastic Gradient Descent): the classic. Takes the plain step, optionally with momentum to keep rolling in a consistent direction.
- **Adam**: the workhorse default. It adapts the step size per parameter automatically, so it trains fast and forgives an imperfect learning rate. The BUILD uses Adam.

The optimizer holds the learning rate and applies the update. In PyTorch you create it once (`optimizer = torch.optim.Adam(...)`) and call `optimizer.step()` each iteration.

---

## 9. Epochs, batches, and batch size

Data is fed to the network in controlled portions:

- A **batch** is a small group of training examples processed together before the weights are updated once. Processing a batch at a time is faster and gives steadier gradients than one example at a time.
- **Batch size** is how many examples are in a batch (for example 16 or 32). Bigger batches are smoother but use more memory; smaller batches are noisier but can generalize better.
- An **epoch** is one full pass over the entire training set. Training runs for many epochs so the network sees the data repeatedly and keeps refining.

On our tiny CPU box, batches are small and epochs are quick. On a real project with millions of examples, one epoch can take hours on a GPU.

---

## 10. Learning rate: the most important knob (recap from Tier 2)

The **learning rate** is the size of each downhill step, exactly as in Tier 2.

- Too high: the loss overshoots and can explode to `inf`/`nan` - divergence. You will meet this in the SURVIVE "loss-goes-nan" scenario.
- Too low: the loss creeps and training stalls.
- Just right: the loss falls smoothly every epoch.

Adam is forgiving, but the learning rate is still the first thing to tune when training misbehaves.

---

## 11. Overfitting, regularization, and dropout

A network with enough capacity can **memorize** the training data instead of learning the general pattern. That is **overfitting**: the training loss keeps falling but the model does badly on new, unseen data. The gap between "great on training data, poor on new data" is the tell.

Tools to fight it:

- **Validation set**: hold out some data the model never trains on. Watch its loss. When training loss falls but validation loss starts rising, you are overfitting. (This is the SURVIVE "overfitting" scenario.)
- **Regularization** (weight decay): gently push weights toward zero so the model stays simple and cannot memorize noise. (Weight decay equals classic L2 regularization under plain SGD; for adaptive optimizers like Adam the two differ, which is why the `AdamW` variant exists - it applies weight decay correctly. You do not need the math here, just know the term.)
- **Dropout**: during training, randomly switch off a fraction of neurons each step. The network cannot lean on any single neuron, so it learns more robust, spread-out patterns. Dropout is on during training and off during prediction. (Modern frameworks implement "inverted dropout" - they scale the surviving activations up during training so no adjustment is needed at prediction time; the framework handles this for you.)
- **Early stopping**: stop training at the epoch where validation loss is lowest, before it starts rising.

A trustworthy consultant always reports how a model does on held-out data, never just on the data it trained on.

---

## 12. Where a real project uses a GPU

Everything above is math a CPU can do. The reason deep learning waited for GPUs is scale. A **GPU** does thousands of multiply-add operations in parallel, which is exactly what forward and backward passes are. On our t3 box with tiny models and tiny datasets, a CPU finishes training in seconds and you need no GPU at all. On a real project - training a large network on millions of examples, or fine-tuning a transformer - a CPU could take days while a GPU takes hours. The code is nearly identical; you just move the model and data onto the GPU. We flag those spots as they come up.

---

## Takeaways

- A neuron is a weighted sum plus a bias, squashed by an activation. A network is many of these in layers.
- Weights and biases are the learned parameters - all the "knowledge" is there.
- Activations (ReLU, softmax) add the nonlinearity that makes deep networks powerful.
- Training loop: forward pass -> loss -> backprop (gradients) -> optimizer step -> repeat over batches and epochs.
- Cross-entropy is the classification loss; Adam is the default optimizer; ReLU + softmax is the default activation combo for a classifier.
- Overfitting is memorizing the training set. Fight it with a validation set, dropout, weight decay, and early stopping.
- CPU is fine for tiny models; a real project reaches for a GPU when the model and data get large.

---

## References

Authoritative sources used to fact-check the concepts in this document.

- Neural networks, activations (ReLU, sigmoid, softmax), and overfitting - Stanford CS231n notes: https://cs231n.github.io/neural-networks-1/ and https://cs231n.github.io/neural-networks-2/
- Backpropagation (the chain rule) - CS231n: https://cs231n.github.io/optimization-2/ and Dive into Deep Learning: https://d2l.ai/chapter_multilayer-perceptrons/backprop.html
- Softmax and cross-entropy loss - Dive into Deep Learning: https://d2l.ai/chapter_linear-classification/softmax-regression.html
- Optimizers (SGD, momentum, Adam) - Dive into Deep Learning: https://d2l.ai/chapter_optimization/adam.html
- Weight decay vs L2 (and AdamW) - Dive into Deep Learning: https://d2l.ai/chapter_linear-regression/weight-decay.html
- PyTorch autograd and the training loop (the framework that runs this): https://docs.pytorch.org/tutorials/beginner/basics/optimization_tutorial.html

Prof. Happy (SUTA Labs)
