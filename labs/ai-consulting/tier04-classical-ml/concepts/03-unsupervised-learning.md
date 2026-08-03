# Concepts 4.3: Unsupervised Learning

**Tier 4 - Classical machine learning.** Teaching reference. Unsupervised learning has no answer key. You hand the algorithm a pile of unlabeled data and ask it to find the structure hiding inside - natural groups, hidden dimensions, or the oddballs that do not fit.

**Who this is for:** DBAs. Imagine a table with no target column. You cannot ask "predict this." Instead you ask "which rows are similar to each other?" or "which rows are weird?" or "can I describe these 50 columns with just 5?"

**Run the snippets:** on your **lab server**, as **ec2-user**:

```bash
python3.12
```

`exit()` to leave. Snippets assume `import numpy as np` and the `sklearn` imports shown inline.

---

## 1. What "unsupervised" means

**Supervised** learning has labels (Concepts 4.2). **Unsupervised** learning has none. There is no "correct answer" to learn toward. The algorithm looks only at the features and finds patterns on its own.

Because there is no answer key, evaluation is harder and more judgment-based. You cannot compute "accuracy" when there is nothing to be accurate against. You judge results by whether the structure it found is useful and makes sense.

The main jobs:

- **Clustering:** group similar rows together.
- **Dimensionality reduction:** describe many columns with fewer.
- **Anomaly detection:** find the rows that do not fit.
- **Association rules:** find things that go together.

---

## 2. Clustering - the concept

Clustering puts rows into groups (clusters) so that rows in the same group are similar and rows in different groups are different. Nobody tells the algorithm what the groups should be; it discovers them.

- **Example:** customer segmentation. You do not know the segments in advance. Clustering finds them - maybe "big spenders," "weekend browsers," "one-time buyers" - and then a human names them.
- **Key idea:** "similar" means "close together" in the feature space. So scaling matters a lot (a column measured in dollars will dominate a column measured 0-1 unless you scale - see Concepts 4.4).

---

## 3. K-means clustering

The most common clustering method. You tell it K (how many clusters you want). It finds K center points and assigns every row to its nearest center, then moves the centers, and repeats until things stop moving.

- **Intuition:** drop K flags on the map, assign each house to its nearest flag, move each flag to the middle of its houses, repeat.
- **When to use:** you want round, roughly equal-sized groups and you have a sense of how many. Fast and scalable.
- **Strengths:** simple, fast, works on large data.
- **Weaknesses:** you must pick K yourself, and its objective (inertia) assumes clusters are convex and isotropic - roughly round blobs of similar size. It responds poorly to elongated or irregularly shaped clusters, and it is sensitive to scale and to outliers (see: scikit-learn Clustering User Guide). Different random starts can give different answers (so set `random_state`).

Tiny example. On your **lab server**, as **ec2-user**:

```python
from sklearn.datasets import make_blobs
from sklearn.cluster import KMeans
import numpy as np

# 300 points that naturally form 3 blobs
X, _ = make_blobs(n_samples=300, centers=3, random_state=42)

# n_init=10 runs the algorithm 10 times and keeps the best. In current
# sklearn the default is n_init="auto" (10 runs with random init, 1 with
# the default k-means++); we set it explicitly for a stable result.
km = KMeans(n_clusters=3, random_state=42, n_init=10)
labels = km.fit_predict(X)

# how many points landed in each cluster
unique, counts = np.unique(labels, return_counts=True)
print("cluster sizes:", dict(zip(unique.tolist(), counts.tolist())))
```

Expected output (yours will differ slightly):

```
cluster sizes: {0: 100, 1: 100, 2: 100}
```

We generated 3 blobs of 100 points each, and k-means recovered 3 clusters of roughly 100 each. Note we IGNORED the true labels (`_`) - clustering never sees them. In real data the sizes will be uneven and you will not know the right K in advance.

---

## 4. Picking K - the elbow method

Since you choose K yourself, how do you pick a good one? A common trick is the elbow method: run k-means for K = 1, 2, 3, ... and plot how tightly packed the clusters are. That tightness is inertia - the sum of squared distances of each point to its assigned cluster center, which sklearn exposes as the `inertia_` attribute (also called the within-cluster sum of squares) (see: scikit-learn KMeans API). Inertia always drops as K rises, but at some point the drop flattens out. That bend, the "elbow," is a reasonable K.

- **Intuition:** more clusters always fit tighter, but past a point you are just splitting hairs. The elbow is where extra clusters stop paying off.

---

## 5. Hierarchical clustering

Instead of picking K upfront, this builds a tree of clusters. It starts with every row as its own cluster, then repeatedly merges the two closest clusters until everything is one big cluster. You cut the tree at whatever level gives you the number of groups you want.

- **Intuition:** a family tree of similarity. Zoom out and you see broad groups; zoom in and you see subgroups.
- **When to use:** when you want to SEE the nested structure, or when you do not want to commit to K in advance. Good for smaller datasets.
- **Strengths:** no need to pick K first, produces an intuitive tree (a dendrogram), can find non-round clusters depending on the linkage.
- **Weaknesses:** slow on large data (it compares many pairs), and once a merge is made it is not undone.

---

## 6. PCA - dimensionality reduction

Principal Component Analysis (PCA) takes data with many columns and squeezes it into fewer columns while keeping most of the information. It finds the directions in which the data varies most and describes each row by its position along those few directions.

- **Intuition:** photographing a 3D object. You lose a dimension but keep a recognizable picture if you pick a good angle. PCA picks the most informative angles.
- **When to use:** too many features (slow models, noise, hard to visualize), or you want to plot high-dimensional data in 2D.
- **Strengths:** cuts columns, removes redundancy, speeds up other models, enables 2D/3D visualization.
- **Weaknesses:** the new columns ("components") are combinations of originals, so they are hard to interpret. And you always lose SOME information. sklearn's PCA centers each feature (subtracts the mean) automatically but does NOT scale, so when your columns are on different scales you should standardize them first with `StandardScaler`, or a large-scale column will dominate the components (see: scikit-learn Decomposition User Guide).

Small example showing how much information each component keeps. On your **lab server**, as **ec2-user**:

```python
from sklearn.datasets import load_iris
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA

X = load_iris().data          # 150 rows, 4 columns
Xs = StandardScaler().fit_transform(X)

pca = PCA(n_components=4).fit(Xs)
print("variance kept per component:",
      [round(v, 2) for v in pca.explained_variance_ratio_])
```

Expected output (yours will differ slightly):

```
variance kept per component: [0.73, 0.23, 0.04, 0.01]
```

Read this as: the first component alone captures 73% of the variation, the first two together capture 96% (0.73 + 0.23). So we could throw away the last two columns, keep just 2, and lose only about 4% of the information. That is the power of PCA: 4 columns down to 2 with almost no loss.

---

## 7. Anomaly detection

Finding the rows that do not fit the pattern - the outliers, the oddballs, the "one of these is not like the others."

- **Example:** fraud detection (a transaction unlike this card's history), fault detection (a sensor reading far outside normal), intrusion detection.
- **How it works:** the algorithm learns what "normal" looks like from the bulk of the data, then flags rows that are far from normal. Methods include Isolation Forest and simple statistical distance.
- **When to use:** rare events, quality control, security, monitoring.
- **Watch out:** "anomaly" does not mean "bad" - it means "unusual." A human still has to decide what an anomaly means. And if your training data already contains lots of the bad stuff, the model may learn to call it normal.

---

## 8. Association rules (market basket analysis)

Finding items that tend to appear together. The classic result: "customers who buy bread and butter often also buy jam."

- **Intuition:** it scans transactions and learns rules of the form "if basket has A and B, it often also has C."
- **Three numbers describe a rule:**
  - **Support:** how often the combination appears at all (is it common enough to care?).
  - **Confidence:** when A and B are present, how often C is too (how reliable is the rule?).
  - **Lift:** how much MORE often C appears with A and B than by pure chance (lift > 1 means a real association, not a coincidence).
- **When to use:** retail recommendations ("frequently bought together"), cross-sell, store layout, web-page co-visits.
- **Watch out:** high support with low lift is just popularity, not a real relationship. Everyone buys milk; that is not an insight.

---

## 9. Choosing an unsupervised method - rough guide

- **Group similar rows, know roughly how many groups?** K-means.
- **Group similar rows, want to explore the nested structure?** Hierarchical clustering.
- **Too many columns / want to visualize / speed up a model?** PCA.
- **Find the weird rows?** Anomaly detection (Isolation Forest).
- **Find what goes with what in transactions?** Association rules.

And a reminder that applies to nearly all of them: SCALE your features first (Concepts 4.4). Unsupervised methods lean heavily on distance, and unscaled columns quietly dominate.

---

## 10. Key takeaways

- Unsupervised learning has no labels; it finds structure on its own.
- Clustering groups similar rows; k-means is fast but needs you to pick K; hierarchical builds a tree and does not.
- PCA reduces many columns to a few while keeping most of the information; check `explained_variance_ratio_`.
- Anomaly detection flags the rows that do not fit; "unusual" is not the same as "bad."
- Association rules find items that go together; judge them with support, confidence, and lift.
- Scale your features first - distance-based methods depend on it.
- There is no "accuracy" here; you judge results by whether they are useful and make sense.

---

## References

- scikit-learn User Guide, Clustering (K-means assumptions, inertia, hierarchical linkage): https://scikit-learn.org/stable/modules/clustering.html
- scikit-learn API, `KMeans` (default `n_clusters=8`, `init="k-means++"`, `n_init="auto"` as of 1.4; `inertia_` = within-cluster sum of squares): https://scikit-learn.org/stable/modules/generated/sklearn.cluster.KMeans.html
- scikit-learn User Guide, Decomposition / PCA (centers but does not scale; `explained_variance_ratio_`): https://scikit-learn.org/stable/modules/decomposition.html
- scikit-learn API, `PCA`: https://scikit-learn.org/stable/modules/generated/sklearn.decomposition.PCA.html
- scikit-learn User Guide, Outlier and novelty detection (Isolation Forest): https://scikit-learn.org/stable/modules/outlier_detection.html
