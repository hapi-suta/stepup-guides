# Concepts 2.3: Probability for AI

**Tier 2 - Mathematics and statistics for AI.** Teaching reference. Every prediction a model makes is a probability, even when it hides behind a single answer. "This is spam" really means "92% chance this is spam". Understanding probability is understanding what your model is actually telling you.

**Who this is for:** DBAs. You already reason about likelihoods informally ("this query probably hit the index"). This makes it precise.

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np`.

---

## 1. The rules of probability

A **probability** is a number between 0 and 1:

- `0` means impossible.
- `1` means certain.
- `0.5` means a coin flip.

Two rules cover almost everything:

- **The probabilities of all outcomes add up to 1.** A coin is heads `0.5` + tails `0.5` = `1`.
- **For events that cannot happen together (mutually exclusive), add to get "either one":** `P(A or B) = P(A) + P(B)`. Rolling a 1 or a 2 on a die is `1/6 + 1/6 = 1/3`. (If the events CAN overlap, you must subtract the double-count: `P(A or B) = P(A) + P(B) - P(A and B)` - see: NIST e-Handbook.)

```python
import numpy as np
rolls = np.random.randint(1, 7, size=100000)   # simulate 100k dice rolls
p_one_or_two = np.mean((rolls == 1) | (rolls == 2))
print(round(p_one_or_two, 3))
```

Expected output (yours will differ slightly):

```
0.334
```

We simulated 100,000 rolls and counted how often we got a 1 or a 2. It lands near the true `1/3 = 0.333`. This is a preview of a huge idea: when you cannot compute a probability directly, you can **simulate** it.

---

## 2. Conditional probability

`P(A | B)` reads "probability of A **given** B" - the chance of A once you already know B happened. The bar means "given".

Knowing B changes the odds. `P(rain)` might be 0.2 in general, but `P(rain | dark clouds)` is much higher. In AI, a classifier constantly computes conditional probabilities: `P(spam | these words appear)`.

The formula:

```
P(A | B) = P(A and B) / P(B)
```

In words: out of all the times B happened, what fraction also had A? (see: NIST e-Handbook, conditional probability). This requires `P(B) > 0`.

---

## 3. Bayes theorem

Bayes theorem lets you flip a conditional probability around. It is the engine behind spam filters, medical-test reasoning, and a lot of AI intuition:

```
P(A | B) = P(B | A) * P(A) / P(B)
```

(see: Wolfram MathWorld, Bayes' Theorem). The denominator `P(B)` is the total probability of B, which you expand over all cases: `P(B) = P(B | A) * P(A) + P(B | not A) * P(not A)`. That expansion is exactly the `p_pos` line in the code below.

The classic example everyone gets wrong. A disease affects 1% of people. A test is 99% accurate. You test positive. What is the chance you actually have the disease? Most people say 99%. The real answer is about 50%, because the disease is rare and false positives pile up.

```python
p_disease = 0.01            # P(A): 1% have it
p_pos_given_disease = 0.99  # P(B|A): test catches it 99% of the time
p_pos_given_healthy = 0.01  # false positive rate 1%
p_healthy = 0.99

# P(B): overall chance of a positive test
p_pos = p_pos_given_disease * p_disease + p_pos_given_healthy * p_healthy

# Bayes: P(disease | positive)
p_disease_given_pos = p_pos_given_disease * p_disease / p_pos
print(round(p_disease_given_pos, 3))
```

Expected output:

```
0.5
```

Only a 50% chance, even after a positive on a 99%-accurate test. The lesson for AI: **base rates matter**. A model that is right 99% of the time on rare events can still be wrong half the time when it fires. Always ask "how common is the thing we are predicting?"

---

## 4. Random variables

A **random variable** is a variable whose value comes from a random process. The result of a die roll, the number of users who click an ad, the height of a random person. We use random variables to model anything uncertain, which in AI is everything: the next word, the label, the noise in the data.

Random variables come in two flavors:

- **Discrete:** countable outcomes (die roll: 1-6; clicks: 0, 1, 2, ...).
- **Continuous:** any value in a range (height, temperature, a model's confidence score).

---

## 5. Distributions

A **distribution** describes how likely each value of a random variable is. Three you must know:

### Normal (Gaussian) distribution

The bell curve. Most values cluster near the average; extremes are rare. Heights, measurement errors, and the sums of many small random effects all look normal. It is defined by its **mean** (center) and **standard deviation** (spread).

```python
import numpy as np
sample = np.random.normal(loc=100, scale=15, size=10000)  # mean 100, sd 15
print(round(sample.mean(), 1), round(sample.std(), 1))
```

Expected output (yours will differ slightly):

```
100.1 15.0
```

We drew 10,000 values centered at 100 with spread 15; the sample recovers those numbers. The normal distribution is the default assumption behind many statistical tests you will meet in Concepts 2.4.

### Bernoulli distribution

A single yes/no trial with probability `p` of success. A coin flip is Bernoulli with `p = 0.5`. "Did the user click?" is Bernoulli. Output: 0 or 1.

```python
clicks = np.random.binomial(n=1, p=0.3, size=10)  # 10 single trials, 30% click
print(clicks)
```

Expected output (yours will differ):

```
[0 1 0 0 1 0 0 0 1 0]
```

### Binomial distribution

Count the successes over `n` independent yes/no trials. "Out of 100 visitors, how many click?" is binomial. Bernoulli is just binomial with `n = 1`, which is why both snippets use `np.random.binomial` and only change `n` (see: NIST e-Handbook, binomial distribution; numpy.random.binomial docs).

```python
successes = np.random.binomial(n=100, p=0.3, size=5)  # 5 experiments of 100 visitors
print(successes)
```

Expected output (yours will differ):

```
[27 34 29 31 25]
```

Each number is how many of 100 visitors clicked in that run, hovering near the expected `100 * 0.3 = 30`.

---

## 6. Expected value

The **expected value** is the long-run average of a random variable. For a distribution, it is each outcome times its probability, all summed. For a fair die: `(1+2+3+4+5+6)/6 = 3.5`. You will never roll a 3.5, but that is the average over many rolls.

```python
outcomes = np.array([1, 2, 3, 4, 5, 6])
probs = np.full(6, 1/6)
expected = np.sum(outcomes * probs)
print(expected)
```

Expected output:

```
3.5
```

In AI, expected value shows up as the average reward (reinforcement learning) or the average loss over a dataset.

---

## 7. Variance and standard deviation

These measure **spread**: how far values typically fall from the mean.

- **Variance** is the average of the squared differences from the mean. Squaring keeps everything positive and punishes big deviations.
- **Standard deviation** is the square root of the variance, back in the original units (dollars, seconds), which makes it easier to interpret.

One thing to know before you trust the number: `np.var` and `np.std` default to `ddof=0`, which divides by N (the population formula - see: numpy.var docs). When your data is a sample and you want to estimate the population's spread, pass `ddof=1` to divide by N-1 (Bessel's correction). The example below uses the default N, so it reports the population variance of these five values.

```python
data = np.array([10, 12, 14, 16, 18])
print("mean:", data.mean())
print("variance:", round(data.var(), 2))
print("std dev:", round(data.std(), 2))
```

Expected output:

```
mean: 14.0
variance: 8.0
std dev: 2.83
```

Two datasets can have the same mean but wildly different spread. A model's predictions being "on average right" means little if the standard deviation is huge - that is high uncertainty. Spread is as important as the average.

---

## Key takeaways

- Probability lives in [0, 1]; all outcomes sum to 1.
- `P(A | B)` = probability of A given B; the bar means "given".
- Bayes theorem flips conditionals; base rates matter - a positive on a 99% test can still be a coin flip.
- Random variables model uncertainty; distributions describe their likely values.
- Normal (bell curve), Bernoulli (one yes/no), binomial (count of yes/no) are the three to know.
- Expected value = long-run average; variance and standard deviation = spread = uncertainty.

Next: **Concepts 2.4 - Statistics**, where we go from "what could happen" to "what does the data actually say".

---

## References

- Wolfram MathWorld, Bayes' Theorem: https://mathworld.wolfram.com/BayesTheorem.html
- NIST/SEMATECH e-Handbook, what is a probability / conditional probability: https://www.itl.nist.gov/div898/handbook/apr/section1/apr131.htm
- NIST/SEMATECH e-Handbook, normal distribution: https://www.itl.nist.gov/div898/handbook/eda/section3/eda3661.htm
- NIST/SEMATECH e-Handbook, binomial distribution: https://www.itl.nist.gov/div898/handbook/eda/section3/eda366i.htm
- numpy.random.normal: https://numpy.org/doc/stable/reference/random/generated/numpy.random.normal.html
- numpy.random.binomial: https://numpy.org/doc/stable/reference/random/generated/numpy.random.binomial.html
- numpy.var / numpy.std (`ddof` default 0 = population): https://numpy.org/doc/stable/reference/generated/numpy.var.html
