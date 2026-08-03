# Survive 02: Dependency Nightmare

Your model was trained 6 months ago with PyTorch 2.0 and transformers 4.28. You need to retrain it. But your environment now has PyTorch 2.1 and transformers 4.36. The training script crashes with cryptic errors. Nobody recorded the original dependencies.

---

## The Disaster

On your **Mac terminal**, run the injection script:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime, timedelta

print("""
SCENARIO: Dependency Nightmare

Timeline:
  6 months ago:
    - Trained alert_classifier_v3 with PyTorch 2.0.1, transformers 4.28.0
    - Deployed to production
    - Model works great: 94% accuracy

  Today:
    - Need to retrain with new data
    - pip install torch transformers (gets latest: 2.1.2, 4.36.0)
    - Run training script...

    ERRORS:
      ImportError: cannot import name 'get_linear_schedule_with_warmup'
        from 'transformers'

      RuntimeError: Weights shape mismatch: expected torch.Size([768, 768]),
        got torch.Size([768, 3072])

      TypeError: __init__() got an unexpected keyword argument 'use_cache'

  What happened:
    - transformers 4.36 moved/renamed some functions
    - Model checkpoint saved with 4.28 architecture isn't compatible with 4.36
    - PyTorch 2.1 changed some tensor operations

  You can't retrain. You can't even load the old model properly.
  And nobody wrote down what versions were used.
""")

# Simulate the dependency mismatch
print("Dependency Versions:")
print("=" * 55)

original = {
    "python": "3.10.12",
    "torch": "2.0.1",
    "transformers": "4.28.0",
    "numpy": "1.24.3",
    "scikit-learn": "1.2.2",
    "tokenizers": "0.13.3",
}

current = {
    "python": "3.11.5",
    "torch": "2.1.2",
    "transformers": "4.36.0",
    "numpy": "1.26.2",
    "scikit-learn": "1.3.2",
    "tokenizers": "0.15.0",
}

print(f"{'Package':>15s}  {'Original':>12s}  {'Current':>12s}  {'Changed':>8s}")
print("-" * 55)

for pkg in original:
    orig = original[pkg]
    curr = current[pkg]
    changed = "YES" if orig != curr else "no"
    print(f"{pkg:>15s}  {orig:>12s}  {curr:>12s}  {changed:>8s}")

breaking = [
    ("transformers", "4.28->4.36", "API renamed: get_linear_schedule_with_warmup moved"),
    ("transformers", "4.28->4.36", "Model architecture changed: config key renamed"),
    ("torch", "2.0->2.1", "Default dtype changed for some operations"),
    ("numpy", "1.24->1.26", "Deprecated function removed"),
]

print(f"\nBreaking Changes:")
for pkg, versions, desc in breaking:
    print(f"  [{pkg} {versions}] {desc}")
PYEOF
```

---

## Investigate

On your **Mac terminal**, find the root cause:

```bash
python3 << 'PYEOF'
print("""
Investigation: Why Dependencies Break Models

Three types of dependency problems:

1. API CHANGES
   Functions get renamed, moved, or removed between versions.
   Example: transformers renamed `get_linear_schedule_with_warmup`
   Your code calls the old name -> ImportError

2. CHECKPOINT INCOMPATIBILITY
   Model weights saved with library version X can't load in version Y.
   The model architecture or serialization format changed.
   Example: model saved with transformers 4.28, loading with 4.36 fails

3. BEHAVIOR CHANGES
   Same function, same inputs, different outputs.
   Example: NumPy changed default random number generator.
   Same seed produces different random numbers -> different train/test split
   -> different model -> different accuracy

Why it happens:
  - Libraries release major updates every few months
  - pip install without version pins gets the latest
  - Nobody tested the training script with newer versions
  - 6 months = eternity in Python ML library land

DBA analogy:
  - Like upgrading PostgreSQL 15 to 16 and finding your extension
    doesn't compile because the internal API changed
  - Or pg_dump from PG15 producing slightly different output in PG16
  - Fix: always test upgrades, pin versions, maintain compatibility
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
import json
from datetime import datetime

print("""
FIX: Three-layer defense against dependency nightmares.

Layer 1: Pin ALL dependencies (requirements.txt with exact versions)
Layer 2: Lock the environment (Docker or virtual environments)
Layer 3: Record environment with every model (model card)
""")

# Layer 1: Pinned requirements
print("Layer 1: Pinned Requirements")
print("=" * 55)

bad_requirements = """# BAD - unpinned (gets latest, breaks things)
torch
transformers
numpy
scikit-learn
"""

good_requirements = """# GOOD - pinned to exact versions
torch==2.0.1
transformers==4.28.0
numpy==1.24.3
scikit-learn==1.2.2
tokenizers==0.13.3
"""

print(f"BAD requirements.txt:")
print(f"  {bad_requirements.strip()}")
print(f"\nGOOD requirements.txt:")
print(f"  {good_requirements.strip()}")

print("""
How to create pinned requirements:
  pip freeze > requirements.txt
  # Captures EXACT versions of everything installed

  pip install -r requirements.txt
  # Installs those exact versions on any machine
""")

# Layer 2: Docker (locked environment)
print(f"\nLayer 2: Docker Lock")
print("=" * 55)

dockerfile = """# Pin the base image (not just 'python:3.11')
FROM python:3.10.12-slim

# Pin pip and setuptools too
RUN pip install --upgrade pip==23.3.1

# Copy pinned requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy code
COPY . /app
WORKDIR /app

CMD ["python", "train.py"]
"""

print(f"  Training Dockerfile:")
for line in dockerfile.strip().split("\n"):
    print(f"    {line}")

print("""
  Build once, run anywhere:
    docker build -t alert-trainer:v3 .
    docker run alert-trainer:v3

  6 months later:
    docker run alert-trainer:v3  # same environment, same results
""")

# Layer 3: Environment recording
print(f"\nLayer 3: Record Environment with Every Model")
print("=" * 55)

def record_environment():
    """Record the full environment for reproducibility."""
    import sys
    import platform

    env = {
        "recorded_at": datetime.now().isoformat(),
        "python": {
            "version": sys.version.split()[0],
            "platform": platform.platform(),
        },
        "packages": {
            "torch": "2.0.1",
            "transformers": "4.28.0",
            "numpy": "1.24.3",
            "scikit-learn": "1.2.2",
        },
        "system": {
            "os": platform.system(),
            "arch": platform.machine(),
        },
    }
    return env

env = record_environment()
print(f"  Environment record:")
print(f"  {json.dumps(env, indent=2)}")

print("""
  Save this alongside every trained model:
    models/
      alert_classifier_v3/
        model.pt              # the model weights
        config.json           # model configuration
        environment.json      # FULL environment record
        requirements.txt      # pinned dependencies
        training_log.json     # experiment tracking data

  Then to reproduce:
    1. Read environment.json
    2. Create a virtual environment with those exact versions
    3. Run the training script
    4. Get the same model
""")

# Recovery procedure
print(f"\nRecovery Procedure (when you're already in trouble):")
print("=" * 55)
print("""
  If you don't have the original requirements.txt:

  1. Check if Docker image exists:
     docker images | grep alert-trainer
     # If yes, run the training inside that image

  2. Check if a pip freeze was logged anywhere:
     - CI/CD logs (GitHub Actions logs pip versions)
     - Model artifacts (might include environment.json)
     - Docker layer history: docker history alert-trainer:v3

  3. Check library changelogs for your version range:
     - transformers: https://github.com/huggingface/transformers/releases
     - Find which version introduced the breaking change
     - Install the version just before the break

  4. Binary search for compatible versions:
     pip install transformers==4.30  # try a version between old and new
     # Keep narrowing until you find one that works

  5. Last resort: install the old version explicitly:
     pip install torch==2.0.1 transformers==4.28.0
     # May conflict with other packages, but at least training works

  DBA parallel:
    This is like recovering from an upgrade with no backup:
    1. Check if old data directory exists
    2. Check pg_upgrade logs
    3. Try pg_dump from the new version
    4. Worst case: rebuild from WAL archives
""")

print("""
Prevention checklist:
  1. PIN all dependencies in requirements.txt (pip freeze)
  2. USE Docker for training environments (reproducible)
  3. SAVE environment.json with every model
  4. TEST with pinned versions before upgrading
  5. KEEP old Docker images (don't delete after deploying)
  6. DOCUMENT the upgrade path when you DO upgrade
  7. RUN a compatibility check before merging dependency updates
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Unpinned dependencies | pip install gets latest, breaks training | Pin exact versions in requirements.txt |
| No environment record | Can't recreate the training environment | Save environment.json with every model |
| Checkpoint incompatibility | Model weights don't load with new library | Pin library versions, use Docker |
| Behavior changes | Same code produces different results | Pin versions + test reproducibility |
| No Docker image | Can't recreate environment at all | Always build and keep Docker images |
