# Capstone: Ship an AI Product - Concepts

This is the final module. Everything you've built across 18 modules comes together here. You'll plan, build, test, deploy, and operate a complete AI product from scratch.

---

## What "Shipping" Means

Shipping isn't just writing code. It's delivering a product that:
1. **Works** - solves the actual problem
2. **Stays working** - handles edge cases, failures, growth
3. **Is safe** - doesn't do harm when it's wrong
4. **Improves** - gets better from feedback
5. **Is observable** - you can tell what it's doing and why

A model in a Jupyter notebook is not shipped. A model behind an API with monitoring, security, versioning, and feedback is shipped.

**DBA parallel:** A PostgreSQL install on your laptop is not "shipped." A production cluster with replication, monitoring, backups, alerting, and runbooks is shipped.

---

## The Product: dbaBrain Alert Classifier

Your capstone product: an AI-powered alert classifier for PostgreSQL databases.

**What it does:**
- Receives database alerts (text + metrics)
- Classifies them (performance, storage, replication, connectivity, security, backup)
- Scores severity (P1-P4)
- Suggests root cause
- Recommends actions
- Learns from DBA feedback

**Stack (all from previous modules):**
| Component | Module | What It Does |
|-----------|--------|-------------|
| Text features | 5-8 | Extract keywords, TF-IDF |
| Classification | 9-10 | Train and evaluate models |
| Embeddings | 8 | Semantic similarity search |
| Pipeline | 12 | Ingest, validate, process alerts |
| API server | 13 | FastAPI endpoint for predictions |
| Experiment tracking | 14 | Track model versions |
| Security | 15 | Input validation, output filtering |
| Multi-modal fusion | 16 | Combine text + metrics |
| Database AI | 17 | Alert taxonomy, severity, root cause |
| Multi-agent | 18 | Orchestrate monitor/classify/diagnose |

---

## Shipping Phases

### Phase 1: Plan (What are we building?)
- Define the problem and success metrics
- Choose the architecture
- List the components needed
- Identify risks and mitigations

### Phase 2: Build (Make it work)
- Feature extraction pipeline
- Classification model
- API endpoint
- Basic monitoring

### Phase 3: Test (Prove it works)
- Unit tests for each component
- Integration tests for the full pipeline
- Behavioral tests (specific scenarios)
- Load tests (can it handle production volume?)

### Phase 4: Deploy (Put it in production)
- Containerize with Docker
- Deploy behind a load balancer
- Set up health checks
- Configure monitoring and alerting

### Phase 5: Operate (Keep it working)
- Monitor accuracy per category
- Track prediction latency
- Manage model versions
- Handle incidents

### Phase 6: Improve (Make it better)
- Collect DBA feedback
- Retrain on new data
- A/B test new models
- Expand capabilities

---

## Success Metrics

Before building, define how you'll know it works:

| Metric | Target | How to Measure |
|--------|--------|---------------|
| Classification accuracy | > 90% | Compare predictions to DBA labels |
| Per-category accuracy | > 80% per category | No category below 80% |
| Prediction latency | < 200ms p95 | Measure API response time |
| Availability | > 99.9% | Uptime monitoring |
| False P1 rate | < 5% | Track paging accuracy |
| Missed P1 rate | 0% | Zero tolerance for missed emergencies |
| DBA feedback rate | > 50% of alerts reviewed | Track feedback submissions |
| Time to resolve | 30% reduction | Compare before/after AI |

The most important metric: **missed P1 rate must be 0%.** An alert classifier that misses a production emergency is worse than no classifier at all.

---

## Architecture Decision Records

Document your key decisions:

**ADR-1: Late fusion over early fusion**
- Why: simpler to debug, handles missing data gracefully
- Trade-off: might miss cross-modal patterns
- Revisit when: accuracy per category drops below 85%

**ADR-2: Keyword + threshold classifier (not deep learning)**
- Why: interpretable, fast, works with small training data
- Trade-off: less accurate on ambiguous cases
- Revisit when: training data exceeds 10,000 labeled examples

**ADR-3: Safety levels for actions**
- Why: AI must never take dangerous actions without approval
- Trade-off: slower remediation for medium-risk actions
- This is non-negotiable - never revisit downward

**ADR-4: DBA feedback loop**
- Why: model improves from corrections, captures expertise
- Trade-off: requires DBA time for reviews
- Mitigate: only request feedback on low-confidence predictions

---

## Common Shipping Mistakes

| Mistake | Why It Happens | How to Avoid |
|---------|---------------|-------------|
| Ship without monitoring | "We'll add it later" | Monitoring is required for launch |
| No fallback plan | "It'll work fine" | Define what happens when AI is wrong |
| Over-engineer first version | "Let's add all features" | Ship MVP, iterate |
| Skip security review | "It's internal" | Security from day one |
| No feedback mechanism | "Users will email us" | Build feedback into the product |
| Test only happy path | "Edge cases are rare" | Test failures, missing data, attacks |

---

## Key Takeaways

1. **Shipping = working product with monitoring, security, and feedback**
2. **Define success metrics before building** (accuracy, latency, safety)
3. **Build in phases** - plan, build, test, deploy, operate, improve
4. **Safety is non-negotiable** - missed P1 rate must be 0%
5. **Document decisions** - ADRs explain why, not just what
6. **MVP first, then iterate** - don't over-engineer version 1
