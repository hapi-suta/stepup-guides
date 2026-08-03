# Interview 01: Multi-Modal AI Questions

---

## Question 1: What is multi-modal AI and when would you use it?

**What they're asking:** Do you understand the concept and its practical applications?

**Answer:**

Multi-modal AI combines multiple data types (text, numbers, images, audio) to make better predictions. Instead of looking at just one type of data, it uses all available information together.

Three reasons to use it:
- **Richer context:** Text says "something is slow" but CPU metrics at 98% tells you exactly what's slow. Neither alone gives the full picture.
- **Redundancy:** If one data source fails, the other can still make predictions (degraded but functional).
- **Cross-validation:** When text and metrics agree, you're more confident. When they disagree, you know to investigate.

When NOT to use it:
- One modality already achieves 95%+ accuracy (adding another won't help much)
- The second modality is expensive and adds less than 3% accuracy
- You don't have aligned data (text and metrics from different time windows)

**DBA parallel:** You already do multi-modal analysis. When diagnosing an issue, you check pg_stat_activity (structured data), error logs (text), Grafana (visual), and maybe even Slack messages (text). You fuse these mentally. Multi-modal AI does the same thing programmatically.

---

## Question 2: Explain early fusion vs late fusion. Which would you choose?

**What they're asking:** Can you design a multi-modal architecture?

**Answer:**

**Late fusion:** Each data type gets its own model. Combine predictions at the end.
```
Text  -> Text Model  -> "performance" (90%)  \
                                               -> Combine -> Final answer
Metrics -> Metric Model -> "performance" (85%) /
```

**Early fusion:** Combine all features first, feed to one model.
```
Text features + Metric features -> One Combined Model -> Final answer
```

Trade-offs:

| Factor | Late Fusion | Early Fusion |
|--------|------------|-------------|
| Debugging | Easy (know which model said what) | Hard (features mixed) |
| Missing data | Graceful (skip missing model) | Needs handling (zero-fill) |
| Cross-modal patterns | Misses them | Catches them |
| Complexity | More models to maintain | One model, more features |
| Adding modalities | Easy (add another model) | Requires retraining |

**My recommendation:** Start with late fusion. It's simpler, more debuggable, and handles missing data naturally. Add early fusion only if you find cross-modal patterns that late fusion misses (like "slow" + high CPU = performance but "slow" + full disk = storage).

**DBA parallel:** Late fusion is like having separate monitoring tools (Grafana for metrics, ELK for logs) and a human combining insights. Early fusion is like one tool that ingests everything (a SIEM). Most teams start with separate tools and consolidate later.

---

## Question 3: How do you handle missing modalities in production?

**What they're asking:** Can you build a robust system that works with partial data?

**Answer:**

Missing modalities are the norm, not the exception. In production:
- 80% of alerts have text + metrics (full data)
- 15% have text only (metrics pipeline lag or failure)
- 5% have metrics only (auto-generated alerts without text)

Four strategies:

1. **Graceful degradation:** Fall back to single-modality prediction. Cap confidence lower when data is missing (85% max for text-only vs 95% for full).

2. **Missing flags:** Include a "is_missing" feature for each modality. The model learns that missing metrics means less certainty.

3. **Modality dropout during training:** Randomly zero-out one modality during 20% of training. Forces the model to work without each modality.

4. **Freshness checks:** Stale data is worse than missing data. If metrics are older than 5 minutes, treat them as missing rather than using outdated values.

The key insight: a prediction with low confidence (from partial data) is better than a wrong prediction with high confidence (from stale data). Always prefer "I'm not sure" over "I'm sure but wrong."

**DBA parallel:** Same as query routing with read replicas. If the replica is current, route reads there. If it's lagging, route to primary. If it's down, still serve reads from primary with higher load. You degrade gracefully, you don't fail completely.

---

## Question 4: How do you know if each modality is actually contributing?

**What they're asking:** Can you evaluate and monitor multi-modal systems?

**Answer:**

Three evaluation methods:

1. **Ablation study:** Remove one modality at a time and measure accuracy drop.
   - Full system: 93% accuracy
   - Without text: 68% accuracy (text contributes 25%)
   - Without metrics: 88% accuracy (metrics contribute 5%)
   - Without both: 25% accuracy (random guessing)

   Run this monthly. If removing a modality doesn't hurt accuracy, it's dead weight.

2. **Feature importance tracking:** Monitor the weight/importance of features from each modality. If all metric features have near-zero weights, the model is ignoring metrics.

3. **Contradiction rate monitoring:** Track how often text and metrics disagree. If they always agree, one is redundant. If they disagree 50% of the time, there's a data quality issue. Sweet spot: 5-15% disagreement (each catches different things).

If a modality isn't contributing:
- First, check data quality (is the pipeline working?)
- Then, try modality dropout training (force the model to use it)
- Finally, do a cost-benefit analysis (is the pipeline worth the cost?)

**DBA parallel:** Like checking `pg_stat_user_indexes`. An index that never gets scanned is wasted disk and slows writes. Either the queries need to change (modality dropout = force usage), or the index should be dropped (remove the modality).

---

## Question 5: Walk me through designing a multi-modal alert system from scratch.

**What they're asking:** Can you architect a complete system?

**Answer:**

Building a multi-modal alert classifier:

**Step 1: Data audit**
- What data types do I have? (text logs, metrics, maybe graphs)
- What's the quality of each? (complete, partial, noisy?)
- What's the latency of each? (text in real-time, metrics every 60s)
- What's the cost of each pipeline?

**Step 2: Feature extraction**
- Text: keyword features (has_cpu, has_disk) + TF-IDF for rare terms
- Metrics: min-max scaled values + missing flags
- Time alignment: snap alerts to nearest metric window

**Step 3: Architecture decision**
- Start with late fusion (separate text and metric classifiers)
- Each model predicts independently
- Combine with weighted voting (start 50/50, adjust based on accuracy)

**Step 4: Handle edge cases**
- Missing metrics: fall back to text-only with capped confidence
- Stale metrics: freshness check (reject >5 min old)
- Contradictions: flag for human review, trust metrics for measurable things
- Vague text: rely more heavily on metrics

**Step 5: Monitoring**
- Per-modality accuracy (ablation study monthly)
- Feature importance trends (are weights stable?)
- Contradiction rate (should be 5-15%)
- Freshness/staleness metrics (metric pipeline health)
- Cost per modality vs accuracy contribution

**Step 6: Iterate**
- If late fusion misses cross-modal patterns, try early fusion for specific categories
- If one modality's accuracy drops, investigate the data pipeline
- If both modalities are strong, consider adding a third (time series trends)

**DBA parallel:** Same approach as designing a monitoring stack.
1. Audit what data you have (pg_stat, logs, Grafana)
2. Extract useful signals from each
3. Start with separate tools, combine insights manually
4. Automate the combination
5. Monitor the monitoring
6. Iterate based on incidents
