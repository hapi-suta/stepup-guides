# Build 04: Docker Deployment

Docker packages your model server into a container - the model, code, dependencies, everything. Run it anywhere: your laptop, a VM, AWS, GCP. No more "it works on my machine."

---

## Step 1. Understand Docker concepts

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Docker Concepts for Model Serving:

What is Docker?
  A container packages your application + all its dependencies into one unit.
  Run the container on any machine and it works identically.

DBA analogy:
  Without Docker: install PostgreSQL 16, install extensions, set postgresql.conf,
    set pg_hba.conf, create databases, create users... every time, on every server.
  With Docker: `docker run postgres:16` - everything is already configured.

Key terms:
  - Image:     A snapshot of your application (like a pg_dump backup)
  - Container: A running instance of an image (like a running PostgreSQL server)
  - Dockerfile: Instructions to build an image (like a setup script)
  - Registry:  Where images are stored (like a backup server for pg_dumps)

Why Docker for model serving?
  1. Reproducibility: same environment everywhere (dev = staging = production)
  2. Isolation: model server doesn't interfere with other processes
  3. Portability: deploy to any cloud with one command
  4. Scaling: run 10 containers behind a load balancer
""")
PYEOF
```

---

## Step 2. Write a Dockerfile

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
A Dockerfile is a recipe for building a Docker image.
Each line is one step, like a runbook.
""")

dockerfile = '''# Dockerfile for Alert Classifier API
# Each line is an instruction that adds a layer to the image

# Start from a Python base image
FROM python:3.11-slim
# python:3.11-slim is a minimal Python image (smaller = faster to build/deploy)
# "slim" means it has Python but not extra tools like gcc

# Set the working directory inside the container
WORKDIR /app
# All subsequent commands run from /app
# Like: cd /app

# Copy requirements first (for Docker layer caching)
COPY requirements.txt .
# COPY copies files from your machine into the container
# We copy requirements.txt FIRST so that pip install is cached
# If code changes but requirements don't, pip install is skipped

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt
# RUN executes a command during image build
# --no-cache-dir saves disk space (don't cache downloaded packages)

# Copy the application code
COPY model_server.py .
COPY models/ ./models/
# Copy code AFTER pip install (code changes more often than dependencies)

# Expose the port the server will listen on
EXPOSE 8000
# EXPOSE documents which port the container uses
# It doesn't actually open the port - that's done with docker run -p

# Health check - Docker will monitor this
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \\
  CMD curl -f http://localhost:8000/health || exit 1
# Docker runs this command every 30 seconds
# If it fails 3 times in a row, the container is marked "unhealthy"
# DBA analogy: like pg_isready checking if PostgreSQL is accepting connections

# Run the server when the container starts
CMD ["uvicorn", "model_server:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
# CMD is the default command when you run the container
# --workers 4 runs 4 server processes (handles more concurrent requests)
# --host 0.0.0.0 listens on all interfaces (required in Docker)
'''

print("Dockerfile:")
print("=" * 70)
print(dockerfile)

# Also show what requirements.txt would look like
requirements = '''fastapi==0.109.0
uvicorn==0.27.0
pydantic==2.5.0
numpy==1.26.0
'''

print("\nrequirements.txt:")
print("=" * 70)
print(requirements)

print("""
Build order matters for caching:
  1. Base image (rarely changes)
  2. Dependencies (occasionally changes)
  3. Application code (frequently changes)

If only your code changes, Docker reuses cached layers 1 and 2.
This makes rebuilds fast (seconds instead of minutes).

DBA analogy: like incremental backups vs full backups.
  Only back up what changed, not everything.
""")
PYEOF
```

---

## Step 3. Build and run with Docker

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Docker Commands for Model Serving:

Build the image:
  docker build -t alert-classifier:v1 .
  # -t gives the image a name and tag
  # . means "use the Dockerfile in the current directory"
  # DBA analogy: like pg_dump - creates a snapshot

Run the container:
  docker run -d -p 8000:8000 --name classifier alert-classifier:v1
  # -d runs in background (detached)
  # -p 8000:8000 maps host port to container port
  # --name gives the container a name (like a database name)
  # DBA analogy: like pg_ctl start

Check container health:
  docker ps
  # Shows running containers (like pg_stat_activity)
  # STATUS column shows "healthy" or "unhealthy"

View logs:
  docker logs classifier
  # Shows server output (like PostgreSQL log files)
  docker logs -f classifier
  # -f follows the log in real time (like tail -f)

Stop the container:
  docker stop classifier
  # Graceful shutdown (like pg_ctl stop -m smart)
  docker kill classifier
  # Force stop (like pg_ctl stop -m immediate)

Remove:
  docker rm classifier
  # Remove stopped container
  docker rmi alert-classifier:v1
  # Remove the image

Common patterns:
  # Run with environment variables
  docker run -d -p 8000:8000 \\
    -e MODEL_VERSION=v3 \\
    -e LOG_LEVEL=info \\
    alert-classifier:v3
  # -e sets environment variables inside the container
  # Never hardcode secrets - use -e or Docker secrets

  # Run with a volume (persistent data)
  docker run -d -p 8000:8000 \\
    -v /host/models:/app/models \\
    alert-classifier:v1
  # -v mounts a host directory inside the container
  # Model files on the host are visible inside the container
  # DBA analogy: like mounting a data directory
""")
PYEOF
```

---

## Step 4. Docker Compose for multi-service setup

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Docker Compose: Run multiple containers together.

A model server usually needs:
  - The model API (FastAPI)
  - A database (PostgreSQL for logging predictions)
  - A monitoring tool (Prometheus/Grafana)

Docker Compose defines all of these in one file.
""")

compose = '''# docker-compose.yml
version: "3.8"

services:
  # Model API server
  classifier:
    build: .
    # build from Dockerfile in current directory
    ports:
      - "8000:8000"
    environment:
      - MODEL_VERSION=v3
      - DATABASE_URL=postgresql://app:secret@db:5432/predictions
      - LOG_LEVEL=info
    depends_on:
      db:
        condition: service_healthy
    # Wait for the database to be healthy before starting
    # DBA analogy: don't start the app until PostgreSQL is ready
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # PostgreSQL for logging predictions
  db:
    image: postgres:16
    # Use the official PostgreSQL 16 image
    environment:
      - POSTGRES_USER=app
      - POSTGRES_PASSWORD=secret
      - POSTGRES_DB=predictions
    volumes:
      - pgdata:/var/lib/postgresql/data
      # Named volume - data persists even if container is removed
    ports:
      - "5433:5432"
      # Map to 5433 on host (5432 might be in use)
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d predictions"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
  # Docker manages this volume
  # Data survives container restarts
'''

print("docker-compose.yml:")
print("=" * 70)
print(compose)

print("""
Docker Compose commands:
  docker compose up -d       # Start all services in background
  docker compose ps          # Show running services
  docker compose logs -f     # Follow all logs
  docker compose down        # Stop and remove all services
  docker compose down -v     # Also remove volumes (deletes data!)

DBA analogy:
  docker compose up   = start the whole cluster (primary + standby + pgbouncer)
  docker compose down = stop the whole cluster
  docker compose ps   = check cluster status
""")
PYEOF
```

---

## Step 5. Production deployment checklist

On your **Mac terminal**, run:

```bash
python3 << 'PYEOF'
print("""
Production Deployment Checklist for Model Serving:

PRE-DEPLOY:
  [ ] Model tested on holdout data (accuracy meets threshold)
  [ ] Shadow mode test completed (no regressions on real traffic)
  [ ] Docker image builds successfully
  [ ] Health check endpoint works
  [ ] API docs are accurate (/docs endpoint)

DOCKER:
  [ ] Base image pinned to specific version (python:3.11-slim, not python:latest)
  [ ] requirements.txt has pinned versions (fastapi==0.109.0, not fastapi)
  [ ] No secrets in Dockerfile or image (use environment variables)
  [ ] HEALTHCHECK defined
  [ ] Non-root user in container (security)
  [ ] .dockerignore excludes unnecessary files (.git, __pycache__, .env)

DEPLOYMENT:
  [ ] Multiple workers configured (--workers 4 or more)
  [ ] Graceful shutdown enabled (uvicorn handles SIGTERM)
  [ ] Resource limits set (CPU, memory)
  [ ] Auto-restart on crash (Docker restart policy: unless-stopped)
  [ ] Rolling deployment (zero-downtime update)

MONITORING:
  [ ] Health check monitored externally
  [ ] Request latency tracked (p50, p95, p99)
  [ ] Error rate tracked
  [ ] Model accuracy tracked (log predictions + ground truth)
  [ ] Resource usage tracked (CPU, memory, disk)

SECURITY:
  [ ] API authentication (API key or OAuth)
  [ ] Rate limiting enabled
  [ ] Input validation on all endpoints
  [ ] HTTPS enabled (TLS termination at load balancer)
  [ ] No debug mode in production

DBA analogy - this is the same checklist you'd use for PostgreSQL:
  [ ] Backup tested (model versioned)
  [ ] Monitoring in place (pg_stat_statements)
  [ ] Connection limits set (max_connections)
  [ ] Authentication configured (pg_hba.conf)
  [ ] Health checks active (pg_isready)
  [ ] Rolling restart for upgrades
""")
PYEOF
```

---

## What You Learned

| Concept | What It Does | DBA Analogy |
|---------|-------------|-------------|
| Dockerfile | Recipe to build a container image | Setup script for PostgreSQL |
| Docker image | Snapshot of your application | pg_dump backup |
| Docker container | Running instance of an image | Running PostgreSQL server |
| Layer caching | Reuse unchanged layers for fast builds | Incremental backups |
| HEALTHCHECK | Docker monitors container health | pg_isready |
| Docker Compose | Run multiple services together | Multi-node cluster setup |
| Volume mounts | Persistent data for containers | Data directory (/pgdata) |
| Environment variables | Configure without code changes | postgresql.conf parameters |
