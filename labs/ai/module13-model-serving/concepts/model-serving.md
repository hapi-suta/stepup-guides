# Model Serving & Deployment - Concepts

You trained a model. It works in a notebook. Now what? Model serving is how you make that model available to other systems - an API that accepts requests and returns predictions. This is the bridge between "it works on my machine" and "it works in production."

---

## Why Should You Care?

A model sitting in a .pt file is like a PostgreSQL backup sitting on disk - it has value, but nobody can use it. Model serving is the equivalent of starting PostgreSQL and accepting connections.

Without serving: you run a script manually, copy-paste results.
With serving: any system can send a request and get a prediction in milliseconds.

---

## The DBA Analogy

| PostgreSQL | Model Serving |
|-----------|---------------|
| Start PostgreSQL, listen on port 5432 | Start model server, listen on port 8000 |
| Client sends SQL query | Client sends HTTP request with data |
| PostgreSQL returns result set | Server returns prediction |
| Connection pooling (pgBouncer) | Request batching / load balancing |
| Read replicas for scale | Multiple model server instances |
| pg_stat_statements for monitoring | Request latency and throughput metrics |
| Rolling restart for upgrades | Canary deployment for new models |
| pg_dump for backup | Model versioning and registry |

You already know how to run a production database server. Model serving follows the same operational patterns.

---

## Key Concepts

### 1. Serving Patterns

**REST API (most common):**
- HTTP endpoint that accepts JSON, returns JSON
- Client sends: `POST /predict {"text": "CPU at 95%"}`
- Server returns: `{"category": "performance", "confidence": 0.92}`
- Tools: FastAPI, Flask, Django
- Best for: most use cases, easy to build and debug

**gRPC:**
- Binary protocol, faster than REST
- Uses Protocol Buffers for serialization
- Best for: high-throughput internal services

**Batch serving:**
- Process many predictions at once, store results
- Run on a schedule (cron)
- Best for: non-real-time workloads (nightly reports, bulk scoring)

For most DBA use cases, REST API with FastAPI is the right choice.

### 2. Model Loading

Models are loaded into memory when the server starts. This can take seconds to minutes depending on model size.

```
Server starts -> Load model from disk -> Model in memory -> Ready for requests
```

Key decisions:
- **Load at startup:** Slower start, but first request is fast
- **Lazy load:** Fast start, but first request waits for model load
- **Warm-up:** Load at startup + send test requests to fill caches

### 3. Request Processing

```
Client request -> Validate input -> Preprocess -> Model inference -> Postprocess -> Response
```

Each step matters:
- **Validate:** Is the input the right format? Are required fields present?
- **Preprocess:** Tokenize text, normalize values, create tensors
- **Inference:** Run the model (the actual prediction)
- **Postprocess:** Convert model output to human-readable response

### 4. Performance Considerations

**Latency** - how long one request takes:
- Target: < 100ms for real-time, < 1s for interactive
- Bottleneck is usually model inference
- CPU inference: 10-100ms (small models), 100ms-1s (large models)
- GPU inference: 1-10ms (small models), 10-100ms (large models)

**Throughput** - how many requests per second:
- Single process: 10-100 requests/second (CPU)
- Multiple workers: multiply by worker count
- Batching: group multiple requests into one inference call

**Concurrency** - handling multiple requests at once:
- Use async I/O for network operations
- Use multiple worker processes for CPU-bound inference
- Use request queuing to handle bursts

### 5. Deployment Strategies

**Single server:**
- One machine running the model server
- Simple, good for development and low traffic
- Risk: single point of failure

**Multiple workers:**
- One machine, multiple processes (uvicorn --workers 4)
- Handles more concurrent requests
- Risk: still one machine

**Container (Docker):**
- Package model + server + dependencies into a container
- Consistent across environments
- Easy to deploy to any cloud

**Kubernetes/Cloud:**
- Multiple containers with auto-scaling
- Load balancing across instances
- Health checks and automatic restarts
- Production-grade for high traffic

For learning: single server with FastAPI.
For production: Docker container with multiple workers.

### 6. Model Versioning

You will deploy many model versions over time. Track them:

```
models/
  alert_classifier/
    v1/              # keyword-based rules
      model.pkl
      metadata.json  # accuracy: 0.82, trained: 2024-01-01
    v2/              # fine-tuned BERT
      model.pt
      metadata.json  # accuracy: 0.94, trained: 2024-02-15
    v3/              # fine-tuned with more data
      model.pt
      metadata.json  # accuracy: 0.96, trained: 2024-03-01
```

Version metadata should include:
- Model accuracy on test set
- Training date and data version
- Dependencies (Python version, library versions)
- Who trained it and why

---

## What You'll Build

| Build | What | Why |
|-------|------|-----|
| 01 - FastAPI Model Server | REST API serving a classifier | Foundation - serve predictions over HTTP |
| 02 - Request Handling | Validation, batching, async | Handle real-world request patterns |
| 03 - Model Versioning | Version management, A/B testing | Deploy new models safely |
| 04 - Docker Deployment | Containerize the model server | Production-ready packaging |
