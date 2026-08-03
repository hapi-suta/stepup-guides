# Interview: Tier 2 - Mathematics and Statistics for AI

**Tier 2 interview prep.** These are the questions an AI-consulting client, a hiring panel, or a skeptical executive will actually ask to see if you understand the math well enough to be trusted. Each entry has the question, a model answer in plain language, and "why they ask" so you know what they are really probing.

The skill being tested across all of these is the same: can you explain rigorous math simply and honestly to someone who does not do math? That is the consultant's superpower.

---

## 1. Why is a model's prediction uncertain?

**Model answer.** A model never sees the whole world - it learns from a limited sample of data, so there is always a gap between the sample and reality. On top of that, the data itself has noise (measurement error, randomness in behavior), and the model is a simplification of a messy process. So the model does not really output "the answer"; it outputs a best estimate with uncertainty around it. A good model reports that uncertainty - for example as a probability ("80% likely spam") or a confidence interval - rather than pretending to be certain. When someone hands you a single number with no range, they are hiding the uncertainty, not removing it.

**Why they ask.** They want to know you will not oversell a model. Consultants who claim false precision lose client trust the first time a "sure thing" prediction is wrong. This question checks that you distinguish an estimate from a fact.

---

## 2. Explain correlation vs causation with an example.

**Model answer.** Correlation means two things move together. Causation means one actually makes the other happen. They are not the same. Classic example: ice cream sales and drowning deaths are strongly correlated - both rise in summer. But ice cream does not cause drowning; hot weather causes both. The hidden third variable, weather, is the real driver. In business you see this constantly: "customers who attend our webinars spend more, so webinars cause spending" - but maybe big, committed companies both attend more webinars and spend more anyway. The only reliable way to prove causation is a controlled experiment, like a randomized A/B test, where you change one thing and hold everything else equal.

**Why they ask.** This is the single most common analytical mistake in business, and acting on a false causal claim wastes real money. They want to see you will catch a stakeholder about to spend a budget on a mere correlation, and that you know the fix (a randomized experiment).

---

## 3. What does the learning rate control?

**Model answer.** The learning rate is the size of the step a model takes each time it adjusts itself during training. Picture walking downhill in fog toward the lowest point - the learning rate is how big each stride is. Too small and training crawls, taking forever and sometimes stalling before it reaches the bottom. Too large and you overshoot the bottom, bounce to the other side, overshoot again, and the training can diverge - the error blows up instead of shrinking. You want it just right: steady, quick progress to the minimum. In practice you tune it, often starting around 0.01 and watching whether the loss falls smoothly.

**Why they ask.** The learning rate is the most important and most commonly mis-set knob in model training. Getting it wrong is a top reason training "just doesn't work." They want to confirm you understand it well enough to diagnose a training run that is diverging or stalling.

---

## 4. Explain a confidence interval to an executive.

**Model answer.** A confidence interval is an honesty range around an estimate. Instead of saying "conversion went up 2%," I say "conversion went up 2%, and we are 95% confident the true improvement is somewhere between 0.5% and 3.5%." The single number could be luck; the range tells you how much to trust it. A narrow range means we are confident. A wide range means we need more data before betting on it. The key executive takeaway: if the range dips below zero, we cannot yet be sure there is any real improvement at all. I give you the range so you can make the decision with your eyes open, not a false sense of precision.

**Why they ask.** Executives make decisions off your numbers. They want to know you will communicate uncertainty in language they can act on, without drowning them in statistics. Refusing to give a bare point estimate is a sign of a trustworthy analyst.

---

## 5. What is a p-value, and does "statistically significant" mean the result is important?

**Model answer.** A p-value answers one question: "if there were really no effect, how likely is it we'd see a result this big just by chance?" A small p-value (below 0.05 by convention) means "this would be very unlikely to happen by luck," so we call the result statistically significant and conclude there is probably a real effect. But significant does not mean large or important. With a huge dataset, a tiny, meaningless difference can be statistically significant. So I always report the effect size alongside the p-value: significance tells you the effect is probably real; effect size tells you whether it is big enough to care about.

**Why they ask.** Misreading p-values is rampant. They want to see you know significance is about "not luck," not "big deal," and that you will not let a technically-significant-but-trivial result drive a decision.

---

## 6. What is cosine similarity and why is it used for semantic search?

**Model answer.** Cosine similarity measures whether two vectors point in the same direction, ignoring their length. It ranges from -1 (opposite) through 0 (unrelated) to 1 (identical direction). In AI, we turn each piece of text into a vector called an embedding, where similar meanings land in similar directions. To find documents that match a query, we turn the query into a vector and pick the stored vectors with the highest cosine similarity. We use cosine rather than plain distance because we care about topic, not length - a short sentence and a long paragraph about the same subject should still count as similar, and cosine ignores the magnitude difference. This is the core mechanic of semantic search and retrieval-augmented generation.

**Why they ask.** Cosine similarity underpins every retrieval and RAG system, which are the most common AI consulting builds. They want to confirm you understand the retrieval engine, not just call an API.

---

## 7. A test is 99% accurate, someone tests positive for a rare disease. Are they almost certainly sick?

**Model answer.** No, and this trips up almost everyone. If the disease affects only 1% of people, then even a 99%-accurate test can leave the odds of actually being sick around a coin flip. The reason is base rates: because the disease is so rare, the small percentage of false positives among the huge healthy population can outnumber the true positives. This is Bayes theorem in action - you have to weigh the test result against how common the condition is to begin with. The lesson for AI: a model that is "99% accurate" on a rare event can still be wrong half the time when it fires an alarm. Always ask how common the thing being predicted actually is.

**Why they ask.** Base-rate neglect leads to catastrophic decisions in fraud detection, medical AI, and anomaly alerting - anywhere the target event is rare. They want to see you reason about base rates before trusting an accuracy number.

---

## 8. What is sampling bias, and how would you catch it in an analysis?

**Model answer.** Sampling bias is when the data you collected does not represent the population you care about, so even a mathematically perfect analysis gives a wrong conclusion. Example: measuring app satisfaction only from users who opened the app today misses everyone who already quit in frustration, so your results look far rosier than reality. To catch it, I ask how the data was collected and whether every relevant group had a fair chance of being included. I compare the sample's makeup (age, region, customer type, tenure) against the true population. If the groups being compared differ on something other than the thing I'm studying, the comparison is confounded. The fix is usually to randomize who goes into each group, which is exactly what a proper A/B test does.

**Why they ask.** Bias is the number-one way a "significant" result is actually garbage, and it is invisible in the math itself. They want to know you interrogate where the data came from, not just crunch it.

---

## 9. Walk me through how gradient descent trains a model.

**Model answer.** Every model has a loss function - a single number measuring how wrong it is on the data, big when predictions are far off, small when they're close. Training means making that number as small as possible. Gradient descent does it step by step: start with a random guess for the model's settings, measure the slope of the loss (which way is downhill), take a small step in that downhill direction, and repeat. The slope is called the gradient; the step size is the learning rate. You keep going until the slope flattens out, meaning you've reached the bottom - the settings that make the model as accurate as it can be. Whether you're fitting a simple line or training a giant language model, it's this same downhill loop, just repeated on far more parameters.

**Why they ask.** Gradient descent is how essentially every modern model learns. Explaining it clearly proves you understand what "training" actually is, which lets you reason about training that fails, costs, and timelines.

---

## 10. When would you use the median instead of the mean, and why?

**Model answer.** I use the median when the data has outliers or a skewed distribution, because the median (the middle value) is not dragged around by extremes, while the mean (the average) is. For example, if six employees earn around $60k and one earns $500k, the mean salary jumps to over $120k, which describes nobody, but the median stays at a realistic $62k. This is why we report median income, median home price, and median latency. As a DBA I already live by this with p50, p95, p99 latency instead of average latency, because a few slow queries can make the average lie. The habit carries straight into AI: report the median and the tail percentiles, not just the average, so you don't hide the bad cases.

**Why they ask.** Choosing the right summary statistic is a basic competence test. It also reveals whether you think about distributions and tails, or just reach for "average" reflexively - which matters a lot when reporting model performance and latency.

---

## Quick-fire round (know these cold)

- **Vector, matrix, scalar?** Scalar is one number, vector is a list of numbers (a row), matrix is a grid (a table).
- **What is an embedding?** A piece of data (text, image) turned into a vector of numbers so a computer can measure similarity and do math on meaning.
- **Normal distribution?** The bell curve; most values near the average, extremes rare; described by mean and standard deviation.
- **Standard deviation?** How spread out the data is around the mean, in the original units.
- **What does a dot product tell you?** How much two vectors agree in direction; the building block of neural networks and similarity.
- **Overfitting in one line?** The model memorized the training data instead of learning the pattern, so it fails on new data.

---

## How to practice

Do not memorize these word for word. Instead, practice saying each answer out loud in under 60 seconds to an imaginary non-technical executive. If you cannot explain it simply, you do not understand it well enough yet - go back to the matching Concepts doc (2.1 through 2.5). The ability to make the math simple and honest is the entire point of this tier.
