# Build 01: Product Planning

Before writing code, define what you're building, why, and how you'll know it works.

---

## Step 1. Product requirements document

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# PRODUCT REQUIREMENTS DOCUMENT (PRD)
# Define the product before building it.
#
# DBA analogy: you don't build a replication cluster without
# first defining: RPO, RTO, number of standbys, failover
# criteria. Same discipline for AI products.
# ============================================================

print("Product Requirements Document: dbaBrain Alert Classifier")
print("=" * 60)

PRD = {
    "product_name": "dbaBrain Alert Classifier",
    "version": "1.0",

    "problem": (
        "DBAs managing 15,000+ databases receive thousands of alerts daily. "
        "Most are noise. Critical alerts get buried. Manual triage takes too long."
    ),

    "solution": (
        "AI-powered alert classifier that categorizes, prioritizes, and "
        "diagnoses database alerts automatically."
    ),

    "users": [
        "On-call DBAs (primary): need fast, accurate alert triage",
        "DBA managers: need trend reports and accuracy metrics",
        "SREs: need API integration with existing alerting tools",
    ],

    "capabilities": [
        {
            "name": "Alert classification",
            "description": "Categorize alerts into 6 types",
            "priority": "P0 (must have)",
            "module_source": "Modules 5-10, 16-17",
        },
        {
            "name": "Severity scoring",
            "description": "Score 0-100, assign P1-P4 priority",
            "priority": "P0 (must have)",
            "module_source": "Module 17",
        },
        {
            "name": "Root cause suggestion",
            "description": "Suggest likely root cause with evidence",
            "priority": "P1 (should have)",
            "module_source": "Module 17",
        },
        {
            "name": "Action recommendation",
            "description": "Suggest remediation steps with risk levels",
            "priority": "P1 (should have)",
            "module_source": "Module 17",
        },
        {
            "name": "DBA feedback loop",
            "description": "Collect corrections, retrain periodically",
            "priority": "P1 (should have)",
            "module_source": "Module 17",
        },
        {
            "name": "Multi-agent orchestration",
            "description": "Coordinate multiple specialist agents",
            "priority": "P2 (nice to have for v1)",
            "module_source": "Module 18",
        },
    ],

    "non_functional": {
        "latency": "< 200ms p95 for classification",
        "availability": "99.9% uptime",
        "accuracy": "> 90% overall, > 80% per category",
        "safety": "Zero missed P1 alerts, zero unauthorized actions",
        "security": "Input validation, output filtering, audit logging",
    },

    "out_of_scope_v1": [
        "Auto-execution of any database actions",
        "Multi-database correlation (analyzing across databases)",
        "Natural language querying of the AI",
        "Image analysis of Grafana dashboards",
    ],
}

# Display the PRD
print(f"\n  Product: {PRD['product_name']} v{PRD['version']}")
print(f"\n  Problem: {PRD['problem'][:80]}...")
print(f"\n  Solution: {PRD['solution'][:80]}...")

print(f"\n  Users:")
for user in PRD['users']:
    print(f"    - {user}")

print(f"\n  Capabilities ({len(PRD['capabilities'])}):")
for cap in PRD['capabilities']:
    print(f"    [{cap['priority']:<20s}] {cap['name']}")
    print(f"      {cap['description']}")

print(f"\n  Non-Functional Requirements:")
for key, value in PRD['non_functional'].items():
    print(f"    {key:<15s} {value}")

print(f"\n  Out of Scope for v1:")
for item in PRD['out_of_scope_v1']:
    print(f"    - {item}")

print("""
Why a PRD matters:
  - Prevents scope creep ("let's also add dashboard analysis!")
  - Sets clear success criteria (> 90% accuracy, < 200ms latency)
  - Prioritizes features (P0 must ship, P2 can wait)
  - Documents what's NOT included (manages expectations)
""")
PYEOF
```

---

## Step 2. Architecture diagram

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# ARCHITECTURE DESIGN
# Define the components and how they connect.
#
# DBA analogy: like designing a database cluster.
# You draw the architecture before provisioning servers.
# ============================================================

print("System Architecture")
print("=" * 55)

ARCHITECTURE = {
    "components": [
        {
            "name": "API Gateway",
            "type": "entry_point",
            "technology": "FastAPI (Module 13)",
            "responsibilities": [
                "Accept alert requests (POST /classify)",
                "Authentication (API key validation)",
                "Rate limiting (60 req/min per client)",
                "Input validation (Pydantic schema)",
            ],
        },
        {
            "name": "Feature Extractor",
            "type": "processing",
            "technology": "Python (Modules 5-8, 16)",
            "responsibilities": [
                "Extract text features (keywords, TF-IDF)",
                "Extract metric features (scale, normalize)",
                "Handle missing modalities",
                "Time-align text and metrics",
            ],
        },
        {
            "name": "Classifier",
            "type": "model",
            "technology": "Python (Modules 9-10)",
            "responsibilities": [
                "Text classification (keyword rules)",
                "Metric classification (threshold rules)",
                "Late fusion (combine predictions)",
                "Confidence scoring",
            ],
        },
        {
            "name": "Severity Scorer",
            "type": "processing",
            "technology": "Python (Module 17)",
            "responsibilities": [
                "Score severity 0-100",
                "Apply environment weighting",
                "Enforce metric floor (critical = P1)",
                "Assign P1-P4 priority",
            ],
        },
        {
            "name": "Diagnostics Engine",
            "type": "processing",
            "technology": "Python (Module 17)",
            "responsibilities": [
                "Root cause matching",
                "Context enrichment (recent alerts)",
                "Evidence gathering",
                "Action recommendation",
            ],
        },
        {
            "name": "Output Filter",
            "type": "security",
            "technology": "Python (Module 15)",
            "responsibilities": [
                "Validate output format",
                "Redact sensitive information",
                "Check action safety levels",
                "Enforce output guardrails",
            ],
        },
        {
            "name": "Feedback Store",
            "type": "storage",
            "technology": "PostgreSQL + JSONB",
            "responsibilities": [
                "Store predictions and DBA feedback",
                "Track accuracy per category",
                "Provide training data for retraining",
                "Audit trail of all decisions",
            ],
        },
        {
            "name": "Monitoring",
            "type": "observability",
            "technology": "Prometheus + logs",
            "responsibilities": [
                "Track prediction latency",
                "Track accuracy metrics",
                "Alert on accuracy degradation",
                "Track pipeline health",
            ],
        },
    ],

    "data_flow": [
        "1. Alert arrives at API Gateway (POST /classify)",
        "2. Input validated (Pydantic schema)",
        "3. Feature Extractor processes text + metrics",
        "4. Classifier predicts category + confidence",
        "5. Severity Scorer assigns P1-P4",
        "6. Diagnostics Engine suggests root cause + actions",
        "7. Output Filter redacts sensitive data",
        "8. Response returned to client",
        "9. Prediction logged to Feedback Store",
        "10. Monitoring tracks metrics",
    ],
}

print(f"\nComponents ({len(ARCHITECTURE['components'])}):")
print("-" * 55)
for comp in ARCHITECTURE['components']:
    print(f"\n  [{comp['type']:>12s}] {comp['name']}")
    print(f"    Tech: {comp['technology']}")
    for r in comp['responsibilities'][:2]:
        print(f"    - {r}")

print(f"\nData Flow:")
print("-" * 55)
for step in ARCHITECTURE['data_flow']:
    print(f"  {step}")

print("""
Every component maps to a module you've already built.
Shipping is assembly + integration + testing + monitoring.
""")
PYEOF
```

---

## Step 3. Risk assessment

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# RISK ASSESSMENT
# Identify what can go wrong and how to handle it.
#
# DBA analogy: like a database risk assessment before
# a major migration. What could go wrong? What's the rollback?
# ============================================================

print("Risk Assessment")
print("=" * 55)

risks = [
    {
        "risk": "Model misclassifies a P1 alert as P4",
        "probability": "medium",
        "impact": "critical",
        "mitigation": "Metric floor: critical metrics always force P1 regardless of text",
        "monitoring": "Track missed P1 rate, alert if > 0",
    },
    {
        "risk": "Classification accuracy drops after retraining",
        "probability": "medium",
        "impact": "high",
        "mitigation": "Shadow mode deployment, per-category accuracy gates, rollback capability",
        "monitoring": "Per-category accuracy dashboard, alert on > 5% drop",
    },
    {
        "risk": "Feedback poisoning (bad DBA corrections)",
        "probability": "low",
        "impact": "high",
        "mitigation": "Trust levels for DBAs, quarantine junior corrections, cross-review",
        "monitoring": "Track correction rate per DBA, flag anomalies",
    },
    {
        "risk": "API overloaded during alert storm",
        "probability": "medium",
        "impact": "medium",
        "mitigation": "Rate limiting, queue overflow to batch processing, scale horizontally",
        "monitoring": "Request rate, queue depth, latency p95",
    },
    {
        "risk": "Metrics pipeline sends stale data",
        "probability": "medium",
        "impact": "high",
        "mitigation": "Freshness checks, variance monitoring, fall back to text-only",
        "monitoring": "Metric age, frozen value detection",
    },
    {
        "risk": "Security: prompt injection via alert text",
        "probability": "low",
        "impact": "medium",
        "mitigation": "Input sanitization, structured output only, output filtering",
        "monitoring": "Injection detection rate, blocked request count",
    },
]

print(f"\n{'Risk':<45s} {'Prob':>6s} {'Impact':>8s}")
print("-" * 65)

for r in risks:
    print(f"\n  {r['risk'][:50]}")
    print(f"    Probability: {r['probability']}, Impact: {r['impact']}")
    print(f"    Mitigation: {r['mitigation'][:60]}")
    print(f"    Monitoring: {r['monitoring'][:60]}")

print(f"""
Top 3 risks by severity (probability * impact):
  1. Misclassify P1 -> Fix: metric floor (non-negotiable)
  2. Accuracy drops after retrain -> Fix: shadow mode + gates
  3. Stale metrics -> Fix: freshness checks + text-only fallback

Every risk has:
  - A mitigation (prevent it from happening)
  - A monitoring metric (detect it quickly if it does happen)
  - A rollback plan (undo the damage)
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| PRD | Define product requirements | Migration plan |
| Success metrics | How you'll know it works | SLA targets |
| Architecture design | Components and connections | Database cluster design |
| Risk assessment | What can go wrong + mitigations | Pre-migration risk review |
| Scope management | What's in and out of v1 | Phase 1 vs Phase 2 of migration |
