# Build 04: Deployment and Operations

Package, deploy, monitor, and operate your AI product in production.

---

## Step 1. Containerize with Docker

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'

# ============================================================
# CONTAINERIZATION
# Package your application so it runs the same everywhere.
#
# DBA analogy: like creating a PostgreSQL Docker image.
# Instead of "install PostgreSQL, configure pg_hba.conf,
# set shared_buffers..." you just run "docker pull postgres:16"
# and it works. Same idea for your AI product.
# ============================================================

print("Containerization: Package for Deployment")
print("=" * 55)

# Show what a Dockerfile would look like for dbaBrain
dockerfile = """
# ---- Dockerfile for dbaBrain Alert Classifier ----
# This file tells Docker how to build your application image.
#
# Think of it as a recipe:
# 1. Start with a base image (Python 3.11)
# 2. Install dependencies
# 3. Copy your code
# 4. Tell Docker how to start the app

# Step 1: Base image
# python:3.11-slim is a small Python image (< 200 MB)
# "slim" means it doesn't include compilers and other tools
# we don't need at runtime
FROM python:3.11-slim

# Step 2: Set working directory inside the container
# All commands after this run inside /app
WORKDIR /app

# Step 3: Install Python dependencies
# Copy requirements.txt first (before code) so Docker can
# cache this layer. If code changes but deps don't,
# Docker won't re-install deps.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Step 4: Copy application code
COPY . .

# Step 5: Create a non-root user (security best practice)
# Never run containers as root. If an attacker gets in,
# they shouldn't have root access.
RUN useradd --create-home appuser
USER appuser

# Step 6: Expose the port the API listens on
EXPOSE 8000

# Step 7: Health check - Docker will restart if this fails
# Checks the /health endpoint every 30 seconds
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \\
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

# Step 8: Start the application
# uvicorn is the ASGI server that runs FastAPI
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
"""

print(dockerfile)

# Show requirements.txt
requirements = """
# ---- requirements.txt ----
# Pin exact versions so builds are reproducible.
# "It worked yesterday" isn't good enough.
# Pin versions so it works the same every time.

fastapi==0.104.1
uvicorn==0.24.0
pydantic==2.5.2
prometheus-client==0.19.0
"""

print(requirements)

# Show docker-compose for the full stack
docker_compose = """
# ---- docker-compose.yml ----
# Runs the full stack: API + PostgreSQL + Prometheus
#
# DBA analogy: like a Patroni cluster definition.
# One file defines all the components and how they connect.

version: '3.8'

services:
  # The AI classifier API
  dbabrain-api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://dbabrain:secret@db:5432/dbabrain
      - ENVIRONMENT=production
      - LOG_LEVEL=info
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '1.0'

  # PostgreSQL for feedback storage
  db:
    image: postgres:16
    environment:
      - POSTGRES_DB=dbabrain
      - POSTGRES_USER=dbabrain
      - POSTGRES_PASSWORD=secret
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dbabrain"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Prometheus for metrics
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

volumes:
  pgdata:
"""

print(docker_compose)

print("""
Docker deployment commands:
  docker compose up -d          # Start all services
  docker compose ps             # Check status
  docker compose logs -f api    # Watch API logs
  docker compose down           # Stop everything

DBA analogy:
  Dockerfile = postgresql.conf + pg_hba.conf (how to configure)
  docker-compose.yml = Patroni config (how to run the cluster)
  docker compose up = systemctl start postgresql (start it)
""")
PYEOF
```

---

## Step 2. Health checks and readiness

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime

# ============================================================
# HEALTH CHECKS
# Know when your service is healthy, degraded, or down.
#
# DBA analogy: like pg_isready for PostgreSQL.
# Before sending traffic, check if the database is accepting
# connections. Same for your AI service.
# ============================================================

print("Health Checks: Know Your Service Status")
print("=" * 55)

class HealthChecker:
    """
    Check the health of all components.

    Three states:
      healthy:  everything works normally
      degraded: some features unavailable but core works
      unhealthy: service should not receive traffic

    DBA analogy:
      healthy = primary accepting reads and writes
      degraded = primary accepting reads, replication lagging
      unhealthy = primary not accepting connections
    """

    def __init__(self):
        # Track component health
        self.components = {
            "classifier": {"status": "healthy", "last_check": None},
            "database": {"status": "healthy", "last_check": None},
            "metrics_collector": {"status": "healthy", "last_check": None},
        }

        # Track service metrics
        self.start_time = datetime.now()
        self.total_requests = 0
        self.total_errors = 0

    def check_classifier(self):
        """
        Check if the classifier is working.
        Run a test prediction and verify the result.
        """
        try:
            # In production: run a known test case through the classifier
            # Here: simulate the check
            test_result = {"category": "performance", "confidence": 0.85}

            if test_result["category"] is not None:
                self.components["classifier"]["status"] = "healthy"
            else:
                self.components["classifier"]["status"] = "unhealthy"

        except Exception as e:
            self.components["classifier"]["status"] = "unhealthy"

        self.components["classifier"]["last_check"] = datetime.now().isoformat()

    def check_database(self):
        """
        Check if the feedback database is reachable.

        DBA analogy: literally pg_isready.
        """
        try:
            # In production: run SELECT 1 against PostgreSQL
            # Here: simulate the check
            db_responding = True

            if db_responding:
                self.components["database"]["status"] = "healthy"
            else:
                self.components["database"]["status"] = "unhealthy"

        except Exception:
            self.components["database"]["status"] = "unhealthy"

        self.components["database"]["last_check"] = datetime.now().isoformat()

    def check_metrics_collector(self):
        """Check if the metrics collection pipeline is working."""
        try:
            # In production: check if metrics are flowing
            metrics_fresh = True  # simulate

            if metrics_fresh:
                self.components["metrics_collector"]["status"] = "healthy"
            else:
                # Degraded: classifier works but without fresh metrics
                self.components["metrics_collector"]["status"] = "degraded"

        except Exception:
            self.components["metrics_collector"]["status"] = "degraded"

        self.components["metrics_collector"]["last_check"] = datetime.now().isoformat()

    def get_health(self):
        """
        Run all checks and return overall health.

        Rules:
          - If classifier is unhealthy -> service is unhealthy
          - If database is unhealthy -> service is degraded
            (can still classify, just can't store feedback)
          - If metrics collector is unhealthy -> service is degraded
            (can still classify using text only)
        """
        self.check_classifier()
        self.check_database()
        self.check_metrics_collector()

        # Determine overall status
        statuses = [c["status"] for c in self.components.values()]

        if "unhealthy" in statuses:
            # Check if it's only non-critical components
            if self.components["classifier"]["status"] == "unhealthy":
                overall = "unhealthy"  # core is down
            else:
                overall = "degraded"  # non-core is down
        elif "degraded" in statuses:
            overall = "degraded"
        else:
            overall = "healthy"

        uptime = (datetime.now() - self.start_time).total_seconds()

        return {
            "status": overall,
            "uptime_seconds": round(uptime, 1),
            "components": self.components,
            "metrics": {
                "total_requests": self.total_requests,
                "total_errors": self.total_errors,
                "error_rate": round(
                    self.total_errors / max(1, self.total_requests) * 100, 2
                ),
            },
        }


# ---- Demonstrate Health Checks ----

checker = HealthChecker()

# Scenario 1: Everything healthy
print("\nScenario 1: All Healthy")
print("-" * 40)
health = checker.get_health()
print(f"  Status: {health['status']}")
for name, comp in health["components"].items():
    print(f"    {name}: {comp['status']}")

# Scenario 2: Database down (degraded)
print("\nScenario 2: Database Down")
print("-" * 40)
checker.components["database"]["status"] = "unhealthy"
# Re-check only classifier and metrics
checker.check_classifier()
checker.check_metrics_collector()
# Database stays unhealthy (simulating outage)

statuses = [c["status"] for c in checker.components.values()]
if checker.components["classifier"]["status"] == "healthy":
    overall = "degraded"
else:
    overall = "unhealthy"

print(f"  Status: {overall}")
for name, comp in checker.components.items():
    print(f"    {name}: {comp['status']}")
print("  Note: Service can still classify alerts (text-only mode)")
print("  Note: Feedback storage disabled until DB recovers")

# Scenario 3: Classifier down (unhealthy)
print("\nScenario 3: Classifier Down")
print("-" * 40)
checker.components["classifier"]["status"] = "unhealthy"
print(f"  Status: unhealthy")
for name, comp in checker.components.items():
    print(f"    {name}: {comp['status']}")
print("  Action: Load balancer stops sending traffic to this instance")
print("  Action: Alert sent to on-call engineer")

print("""
Health check endpoints:
  GET /health          -> quick check (for load balancer)
  GET /health/detailed -> full component status (for debugging)
  GET /ready           -> is the service ready for traffic?

The load balancer uses /health to decide where to send traffic.
If /health returns unhealthy, traffic goes to other instances.

DBA analogy:
  /health = pg_isready (can I connect?)
  /health/detailed = pg_stat_activity + pg_stat_replication (what's happening?)
  /ready = is this standby caught up enough to serve reads?
""")
PYEOF
```

---

## Step 3. Model versioning

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime

# ============================================================
# MODEL VERSIONING
# Track which model version is running and its performance.
#
# DBA analogy: like tracking PostgreSQL versions across your fleet.
# "Which version of pg is running on pg-primary-3?"
# "When did we upgrade from 15 to 16?"
# Same discipline for AI models.
# ============================================================

print("Model Versioning: Track Every Model Change")
print("=" * 55)

class ModelVersion:
    """
    Track a specific version of the model.

    Every time you change the model (new keywords, new thresholds,
    new weights), create a new version. Never modify in place.

    DBA analogy: like database migrations.
    Migration 001: create users table
    Migration 002: add email column
    You never edit migration 001. You create 002.
    Same for model versions.
    """

    def __init__(self, version, description, config, metrics=None):
        # version: semantic versioning (major.minor.patch)
        #   major: breaking changes (new categories, different output format)
        #   minor: improvements (new keywords, better thresholds)
        #   patch: bug fixes (typo in keyword, wrong threshold value)
        self.version = version
        self.description = description
        self.config = config
        self.metrics = metrics or {}
        self.created_at = datetime.now().isoformat()
        self.status = "candidate"  # candidate -> active -> retired

    def to_dict(self):
        return {
            "version": self.version,
            "description": self.description,
            "status": self.status,
            "created_at": self.created_at,
            "metrics": self.metrics,
            "config_keys": list(self.config.keys()),
        }


class ModelRegistry:
    """
    Registry of all model versions.

    Keeps track of:
      - Which version is currently active
      - History of all versions
      - Performance metrics per version

    DBA analogy: like a pgBackRest catalog.
    It knows every backup, when it was taken, and if it's valid.
    You can restore to any point. Same for models - you can
    roll back to any version.
    """

    def __init__(self):
        self.versions = {}
        self.active_version = None

    def register(self, version):
        """Register a new model version."""
        self.versions[version.version] = version
        print(f"  Registered: v{version.version} ({version.description})")

    def promote(self, version_id):
        """
        Promote a version to active (production).

        Before promoting:
          1. Run the test suite against this version
          2. Compare metrics to the current active version
          3. Only promote if metrics are equal or better
        """
        if version_id not in self.versions:
            print(f"  ERROR: Version {version_id} not found")
            return False

        new_version = self.versions[version_id]

        # Check if new version meets quality gates
        if self.active_version:
            current = self.versions[self.active_version]
            current_accuracy = current.metrics.get("accuracy", 0)
            new_accuracy = new_version.metrics.get("accuracy", 0)

            if new_accuracy < current_accuracy:
                print(f"  BLOCKED: v{version_id} accuracy ({new_accuracy}) "
                      f"< current ({current_accuracy})")
                return False

        # Retire old version
        if self.active_version and self.active_version in self.versions:
            self.versions[self.active_version].status = "retired"

        # Promote new version
        new_version.status = "active"
        self.active_version = version_id
        print(f"  Promoted: v{version_id} is now active in production")
        return True

    def rollback(self, version_id):
        """
        Roll back to a previous version.

        DBA analogy: like PITR (Point-In-Time Recovery).
        Something went wrong? Restore to the last known good state.
        """
        if version_id not in self.versions:
            print(f"  ERROR: Version {version_id} not found")
            return False

        if self.active_version:
            self.versions[self.active_version].status = "retired"

        self.versions[version_id].status = "active"
        self.active_version = version_id
        print(f"  Rolled back to v{version_id}")
        return True

    def list_versions(self):
        """Show all versions and their status."""
        print(f"\n  {'Version':<10s} {'Status':<12s} {'Accuracy':<10s} Description")
        print(f"  {'-'*10} {'-'*12} {'-'*10} {'-'*30}")
        for v in self.versions.values():
            accuracy = v.metrics.get("accuracy", "N/A")
            if isinstance(accuracy, float):
                accuracy = f"{accuracy:.1%}"
            print(f"  {v.version:<10s} {v.status:<12s} {str(accuracy):<10s} {v.description}")


# ---- Demonstrate Model Versioning ----

registry = ModelRegistry()

# Version 1.0.0: Initial release
v1 = ModelVersion(
    version="1.0.0",
    description="Initial release - keyword classifier",
    config={"keywords_per_category": 5, "fusion": "late"},
    metrics={"accuracy": 0.85, "p1_recall": 0.90},
)
registry.register(v1)
registry.promote("1.0.0")

# Version 1.1.0: Improved keywords
v2 = ModelVersion(
    version="1.1.0",
    description="Added 20 new keywords from DBA feedback",
    config={"keywords_per_category": 8, "fusion": "late"},
    metrics={"accuracy": 0.91, "p1_recall": 0.95},
)
registry.register(v2)
registry.promote("1.1.0")

# Version 1.2.0: Bad version (accuracy dropped)
v3 = ModelVersion(
    version="1.2.0",
    description="Experimental: TF-IDF features",
    config={"keywords_per_category": 8, "fusion": "late", "tfidf": True},
    metrics={"accuracy": 0.82, "p1_recall": 0.88},
)
registry.register(v3)

print("\nAttempt to promote v1.2.0 (lower accuracy):")
registry.promote("1.2.0")  # Should be blocked!

# Show all versions
print("\nAll versions:")
registry.list_versions()

# Simulate: v1.1.0 starts having issues in production
print("\nIncident: v1.1.0 misclassifying new alert patterns")
print("Action: Roll back to v1.0.0")
registry.rollback("1.0.0")

print("\nAfter rollback:")
registry.list_versions()

print("""
Model versioning rules:
  1. Never modify a deployed model in place (create a new version)
  2. Quality gates: new version must meet accuracy thresholds
  3. Shadow mode: run new version alongside old one before promoting
  4. Instant rollback: can revert to any previous version
  5. Audit trail: know exactly which version made every prediction

DBA analogy:
  Model version = PostgreSQL minor version (16.1, 16.2, 16.3)
  Promote = upgrade primary to new version
  Quality gate = run regression tests before upgrade
  Rollback = pg_upgrade --rollback (revert if something breaks)
  Shadow mode = run new version on standby first
""")
PYEOF
```

---

## Step 4. Incident response

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
from datetime import datetime

# ============================================================
# INCIDENT RESPONSE
# What to do when things go wrong in production.
#
# DBA analogy: like a database incident runbook.
# "Primary is down. What do we do?"
# You don't figure it out during the outage.
# You write the runbook BEFORE the outage.
# ============================================================

print("Incident Response: When Things Go Wrong")
print("=" * 55)

# Define incident severity levels
INCIDENT_LEVELS = {
    "SEV1": {
        "name": "Critical",
        "description": "AI system completely down or making dangerous decisions",
        "examples": [
            "Classifier returns errors for all requests",
            "All P1 alerts being classified as P4",
            "System auto-executing actions without approval",
        ],
        "response_time": "15 minutes",
        "who_responds": "On-call engineer + engineering lead",
        "communication": "Slack channel + email to stakeholders",
    },
    "SEV2": {
        "name": "Major",
        "description": "AI system degraded - partial functionality lost",
        "examples": [
            "One category has < 50% accuracy",
            "Latency > 2 seconds (10x normal)",
            "Feedback loop not recording corrections",
        ],
        "response_time": "1 hour",
        "who_responds": "On-call engineer",
        "communication": "Slack channel",
    },
    "SEV3": {
        "name": "Minor",
        "description": "AI system working but with reduced quality",
        "examples": [
            "Overall accuracy dropped 5% from baseline",
            "Metrics pipeline delayed (using stale data)",
            "One non-critical endpoint slow",
        ],
        "response_time": "Next business day",
        "who_responds": "Assigned engineer",
        "communication": "Ticket created",
    },
}

print("\nIncident Severity Levels:")
print("-" * 55)
for level, info in INCIDENT_LEVELS.items():
    print(f"\n  {level}: {info['name']}")
    print(f"    {info['description']}")
    print(f"    Response: {info['response_time']}")
    print(f"    Who: {info['who_responds']}")
    print(f"    Examples:")
    for ex in info['examples'][:2]:
        print(f"      - {ex}")


# ---- Incident Response Runbook ----

print("\n\nIncident Response Runbook")
print("=" * 55)

runbook = {
    "step_1_detect": {
        "name": "Detect",
        "actions": [
            "Check monitoring dashboard for anomalies",
            "Review error rate and latency metrics",
            "Check per-category accuracy scores",
            "Look at recent deployment or config changes",
        ],
    },
    "step_2_assess": {
        "name": "Assess",
        "actions": [
            "Determine severity level (SEV1/SEV2/SEV3)",
            "Identify affected users and scope of impact",
            "Check: are P1 alerts still being caught? (safety check)",
            "Decide: rollback needed immediately?",
        ],
    },
    "step_3_mitigate": {
        "name": "Mitigate",
        "actions": [
            "If classifier wrong: roll back to previous model version",
            "If overloaded: enable rate limiting, scale up",
            "If safety issue: activate kill switch (recommend_only mode)",
            "If data issue: switch to text-only classification",
        ],
    },
    "step_4_fix": {
        "name": "Fix",
        "actions": [
            "Identify root cause (don't just fix symptoms)",
            "Implement fix in development environment",
            "Test fix against the failing scenarios",
            "Deploy fix through normal pipeline (not hotfix to prod)",
        ],
    },
    "step_5_postmortem": {
        "name": "Postmortem",
        "actions": [
            "Write timeline of events",
            "Identify root cause and contributing factors",
            "List action items to prevent recurrence",
            "Share with team (blameless - focus on systems, not people)",
        ],
    },
}

for step_key, step in runbook.items():
    print(f"\n  Step: {step['name']}")
    for action in step["actions"]:
        print(f"    [ ] {action}")


# ---- Postmortem Template ----

print("\n\nPostmortem Template")
print("=" * 55)

postmortem_template = """
  INCIDENT POSTMORTEM
  -------------------
  Date:     [DATE]
  Severity: [SEV1/SEV2/SEV3]
  Duration: [START TIME] to [END TIME] ([DURATION])
  Author:   [YOUR NAME]

  Summary:
    [One sentence describing what happened]

  Impact:
    - Users affected: [NUMBER]
    - Alerts misclassified: [NUMBER]
    - P1 alerts missed: [NUMBER]
    - Duration of impact: [DURATION]

  Timeline:
    [TIME] - First anomaly detected
    [TIME] - Alert triggered / human noticed
    [TIME] - Investigation started
    [TIME] - Root cause identified
    [TIME] - Mitigation applied
    [TIME] - Full resolution confirmed

  Root Cause:
    [What actually broke and why]

  Contributing Factors:
    1. [Factor that made it worse]
    2. [Factor that delayed detection]
    3. [Factor that made recovery harder]

  Action Items:
    1. [MUST DO] [Action to prevent recurrence]
    2. [SHOULD DO] [Action to detect faster]
    3. [NICE TO HAVE] [Action to recover faster]

  Lessons Learned:
    - [What we learned]
    - [What we'd do differently]
"""

print(postmortem_template)

print("""
Key principles:
  1. Detect fast: monitoring should catch issues before users report them
  2. Mitigate first, fix second: stop the bleeding before surgery
  3. Safety first: when in doubt, switch to recommend_only mode
  4. Blameless postmortems: systems fail, not people
  5. Action items have owners and deadlines

DBA analogy:
  This IS a DBA runbook. Same structure, same discipline.
  The only difference is the system is an AI classifier
  instead of a PostgreSQL cluster. The operational practices
  are identical.
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Docker containerization | Package app to run anywhere | PostgreSQL Docker image |
| Health checks | Know when service is healthy/degraded/down | pg_isready |
| Model versioning | Track every model change with rollback | Database migrations + PITR |
| Incident response | Structured plan for when things break | DBA incident runbook |
| Quality gates | Block bad models from production | Regression tests before upgrade |
| Postmortem | Learn from failures without blame | Post-incident review |
