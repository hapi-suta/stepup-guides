# Interview: Tier 4 - Classical Machine Learning

**Tier 4 interview prep.** These are the questions an AI-consulting client, a hiring panel, or a skeptical executive will actually ask when they want to know if you understand classical machine learning well enough to advise them. Tier 4 is not about deep learning or fancy models. It is about judgment: knowing when to use ML, which metric matters, what can go wrong, and how to ship responsibly. Each entry has the question, a model answer in plain language, and "why they ask".

---

## 1. When is machine learning the WRONG tool?

**Model answer.** ML is the wrong tool more often than people think. It is wrong when a simple rule already works, for example "block any login from a new country and device at the same time" - if a handful of if-statements catch most of the problem, ship those, not a model. It is wrong when the answer is a fixed lookup, like a tax table or a shipping-rate chart, because there is a correct answer you can just look up, no prediction needed. It is wrong when there is no historical data with known outcomes to learn from, because a supervised model needs examples of the right answer. And it is wrong when nobody can state exactly what the model should predict in one clear sentence. As a consultant my first job is often to talk a client OUT of ML and toward a cheaper rule or lookup that they can understand and maintain.

**Why they ask.** They want to know you will not sell them an expensive model just because it is fashionable. Recommending the simplest thing that works is a sign of seniority and honesty.

---

## 2. Explain precision versus recall, and the cost of each error type for fraud detection.

**Model answer.** Precision answers "when the model says fraud, how often is it right?" Recall answers "of all the real fraud, how much did we catch?" They pull against each other: chase every possible fraud and you catch more (high recall) but you also flag lots of honest customers (low precision); only flag the obvious cases and you are usually right (high precision) but you miss the sneaky ones (low recall). For fraud the two mistakes cost very different amounts. A false negative - real fraud we let through - is a direct financial loss and a chargeback. A false positive - an honest transaction we flag - costs a few minutes of review and maybe a mildly annoyed customer. Because the miss is far more expensive, we usually tune fraud models toward recall, accepting more false alarms to stop more fraud, as long as the review team can handle the volume.

**Why they ask.** They want to see that you connect a model metric to real money and that you can reason about which mistake the business can better afford.

---

## 3. What is data leakage and how do you prevent it?

**Model answer.** Data leakage is when the model accidentally gets to see information at training time that it would not have at prediction time, so it looks amazing in testing and then fails in production. A classic example is predicting churn using a feature like "account_closed_date" - that field only gets filled in after the customer has already churned, so it is a giveaway. Another is scaling or filling missing values using the whole dataset before splitting, which lets the test set leak into the training set. I prevent leakage by splitting into train and test first, then doing all preprocessing inside the training data only and applying it to the test data afterward - scikit-learn Pipelines make this automatic. I also review every feature and ask "would we truly know this value at the moment we make the prediction?" If not, the feature is dropped.

**Why they ask.** Leakage is the number one reason a model that "worked in the lab" dies in production. They want to know you would catch it before it embarrasses everyone.

---

## 4. What is a model card and why ship one?

**Model answer.** A model card is a short document that ships with the model and describes what it is, what it is for, and where it should not be used. It typically covers the intended use, the training data and its known gaps, the performance numbers broken down by important groups, the known limitations and biases, and who to contact. You ship one because months later nobody remembers how the model was built or what it was allowed to do, and someone will try to reuse it for a purpose it was never tested on. The model card is the guardrail against that. It also matters for trust and for regulation - if a decision is ever questioned, the card is your paper trail showing you built it responsibly.

**Why they ask.** They want to know you think past the demo to the model's whole life in production, including accountability and reuse risk.

---

## 5. Explain overfitting versus underfitting, and how you would diagnose each.

**Model answer.** Underfitting is when the model is too simple to capture the pattern, so it does badly on both the training data and new data - it never really learned. Overfitting is the opposite: the model memorized the training data, including its noise, so it looks great on training data but does badly on new data. I diagnose by comparing training performance to test performance. If both are poor, that is underfitting - I add features or use a more capable model. If training is great but test is much worse, that is overfitting - I simplify the model, add more data, or use regularization and cross-validation. The gap between train and test scores is the tell.

**Why they ask.** It is the most basic health check on any model. They want to confirm you actually validate on held-out data instead of trusting training accuracy.

---

## 6. Why is accuracy misleading on imbalanced data, and what would you use instead?

**Model answer.** Accuracy is just the percent of predictions that are correct, which sounds fine until the classes are lopsided. If only 1 percent of transactions are fraud, a model that says "never fraud" for everything is 99 percent accurate and completely useless - it never catches a single fraud. So on imbalanced problems I ignore raw accuracy and look at precision, recall, and the F1 score for the rare class, plus the confusion matrix to see the actual counts. I also like the precision-recall curve because it focuses on the rare positive class. The metric has to reward catching the thing we actually care about, not just being right about the boring majority.

**Why they ask.** Imbalanced data is everywhere - fraud, churn, disease, defects. They want to know you will not be fooled by a big accuracy number that hides a broken model.

---

## 7. How would you choose between logistic regression and a random forest for a client?

**Model answer.** I start with logistic regression, not because it is fancier but because it is simple, fast, and easy to explain - I can tell a client exactly how each feature pushes the prediction up or down. If it hits the business target, we stop there. I move to a random forest when the relationships in the data are more complex and non-linear, or when logistic regression underperforms and we have enough data to support a heavier model. The tradeoff is interpretability: a random forest usually predicts a bit better but is harder to explain, and in regulated settings like lending or hiring that explainability can be a legal requirement. So the choice is not "which is more accurate" alone - it is accuracy weighed against how much the client needs to explain and maintain the model.

**Why they ask.** They want to see you pick models based on the client's real constraints - explainability, regulation, maintenance - not just chase the highest score.

---

## 8. What does a confusion matrix tell a business stakeholder?

**Model answer.** A confusion matrix is a simple two-by-two count of what the model got right and wrong: how many real positives it caught, how many it missed, how many false alarms it raised, and how many negatives it correctly left alone. For a stakeholder I translate those four boxes into their world. For a churn model I would say "out of 100 customers who were going to cancel, we correctly flagged 78 and missed 22, and we bothered 30 happy customers by mistake". That turns an abstract score into headcounts and consequences the business can weigh. It also makes the precision-recall tradeoff concrete, because they can literally see the misses and the false alarms as numbers.

**Why they ask.** They want to know you can make model behavior legible to non-technical people who have to sign off on it.

---

## 9. How do you detect and respond to concept drift after deployment?

**Model answer.** Concept drift is when the world changes after you ship, so the patterns the model learned no longer hold and its accuracy quietly decays - new fraud tactics, a new product line, a changed customer mix. I detect it by monitoring the model's live performance against real outcomes over time, watching for a drop in recall or precision, and also by watching the input data itself for shifts in distribution, like a feature whose average suddenly moves. When drift shows up, the response is usually to retrain the model on fresh, recent data, and sometimes to add new features that capture the new behavior. That is why I always agree on a retraining cadence and an owner up front - a model is not a "build it once" project, it is a thing that needs ongoing care.

**Why they ask.** Many teams deploy a model and forget it. They want to know you plan for the model to decay and have a maintenance answer ready.

---

## 10. How would you explain a model's decision to a non-technical stakeholder?

**Model answer.** I avoid math and talk about which factors mattered most. For a simple model like logistic regression I can point to the features with the biggest weight and say "the strongest signals for churn were fewer orders in the last month and a recent support complaint". For a more complex model I use feature-importance scores or a tool like SHAP to show, for one specific prediction, which factors pushed it toward "yes" and which pushed against. The goal is not to expose the internals - it is to give the stakeholder a plain story they can trust and act on, and to let them sanity-check whether the model is keying off something reasonable rather than a proxy for something we should not use. If I cannot explain roughly why a model decided something, that is a red flag I raise, not something I hide.

**Why they ask.** Interpretability builds trust and is often required by regulation. They want to know you can bridge the gap between the model and the people who have to stand behind its decisions.

---

## How to use this file

Read a question, cover the answer, and say your version out loud in your own words. The panel is not testing whether you memorized definitions - they are testing whether you can reason about ML like a consultant: simplest tool first, metrics tied to money, honest about what can go wrong, and responsible all the way through deployment.
