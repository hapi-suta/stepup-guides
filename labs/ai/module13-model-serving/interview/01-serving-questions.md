# Interview 01: Model Serving Questions

---

## Question 1: How do you serve a trained model in production?

**What they're asking:** Can you go from a .pt file to a running API?

**Answer:**

The standard approach is a REST API with FastAPI:

1. **Load the model at server startup** - read the model file (.pt, .pkl) into memory once. Don't reload per-request.

2. **Define request/response schemas with Pydantic** - validate incoming data (required fields, types, value ranges) before it reaches the model. Reject bad input early.

3. **Create a /predict endpoint** - accepts POST requests with JSON body, runs preprocessing (tokenize, normalize), runs model inference, returns the prediction as JSON.

4. **Run with uvicorn** - the ASGI server handles HTTP connections and routes to FastAPI. Use multiple workers (--workers 4) for concurrency.

5. **Package with Docker** - Dockerfile includes Python, dependencies, model file, and server code. Consistent across environments.

For batch workloads (not real-time), skip the API and use a cron job that reads from a database, runs predictions, and writes results back.

**DBA parallel:** Starting a model server is like starting PostgreSQL. Load shared_buffers (model into memory), listen on a port (uvicorn --port 8000), accept connections (HTTP requests), return results (JSON predictions).

---

## Question 2: How do you handle model updates without downtime?

**What they're asking:** Can you deploy new models safely?

**Answer:**

Three deployment strategies, from safest to fastest:

**Shadow mode** (zero risk): Run the new model alongside production. Both models process every request, but only the production model's answer is returned to the client. Compare results offline. If the new model is clearly better after 1-7 days, promote it.

**A/B testing** (low risk): Route 10-20% of real traffic to the new model. Both models serve real responses. Compare accuracy, confidence, and latency. Gradually increase traffic to the new model if metrics are better.

**Rolling deployment** (moderate risk): Deploy the new model to one container at a time. Monitor metrics after each container. If metrics degrade, stop the rollout and rollback. Kubernetes does this automatically with a Deployment resource.

Key infrastructure: model registry that tracks all versions with metadata (accuracy, training date, data version). Enables instant rollback by switching the "active" pointer back to the previous version.

**DBA parallel:** Shadow mode is like testing a new query plan with EXPLAIN ANALYZE without changing the actual plan. A/B testing is like routing some reads to a new replica. Rolling deployment is like upgrading PostgreSQL one node at a time in a cluster.

---

## Question 3: What's cold start and how do you solve it?

**What they're asking:** Do you understand real operational problems with model serving?

**Answer:**

Cold start is when a model server starts (or restarts) and takes seconds to minutes loading the model into memory. During this time, all requests fail.

The danger: if the server crashes and restarts, there's a window where predictions are unavailable. For alert classification, this means critical alerts go unrouted.

Solutions:

1. **Proper readiness probe** - don't report "ready" until the model is actually loaded and can serve predictions. Kubernetes/load balancer won't route traffic to an unready instance.

2. **Fallback model** - use a lightweight classifier (keyword rules) that's available instantly. Lower accuracy, but better than 503 errors. Switch to the ML model once it's loaded.

3. **Multiple replicas** - run at least 2 instances. If one crashes, the other handles traffic while the crashed one restarts. Kubernetes rolling updates ensure at least one instance is always ready.

4. **Model pre-warming** - after loading the model, send a few test predictions to warm up caches and JIT compilation. The first real request is as fast as the hundredth.

**DBA parallel:** Cold start is like PostgreSQL WAL recovery after a crash. The fix is the same - hot standby (another instance ready to serve), and don't promote until recovery is complete (readiness probe).

---

## Question 4: How do you monitor a model API in production?

**What they're asking:** Do you treat model serving like a real production service?

**Answer:**

Four categories of monitoring:

**Request metrics:**
- Requests per second (throughput)
- Latency: p50, p95, p99 (not just average - p99 shows worst-case)
- Error rate (5xx responses / total responses)
- Status code distribution (200, 422, 500, 503)

**Model metrics:**
- Prediction distribution (are categories balanced or skewed?)
- Average confidence score (dropping confidence = model uncertainty)
- Input drift (are incoming messages different from training data?)
- Accuracy when ground truth is available (was the prediction correct?)

**Resource metrics:**
- CPU utilization (model inference is CPU-heavy)
- Memory usage (should be flat, not growing - growing = memory leak)
- Container restarts (frequent restarts = stability problem)
- Queue depth (if using async processing)

**Business metrics:**
- How many alerts were correctly routed?
- How many were misclassified and needed manual correction?
- Time from alert to classification (end-to-end latency)

Alert on: error rate > 1%, p99 latency > 500ms, memory growing, prediction confidence dropping, zero predictions in 5 minutes.

**DBA parallel:** This is pg_stat_statements (request metrics) + pg_stat_bgwriter (resource metrics) + pg_stat_replication (health metrics) + business KPIs. Same monitoring discipline, different metrics.

---

## Question 5: Explain the tradeoffs between CPU and GPU inference, single-server and distributed.

**What they're asking:** Can you make infrastructure decisions for model serving?

**Answer:**

**CPU vs GPU:**

CPU inference:
- Works for small models (keyword rules, small neural networks)
- Latency: 10-100ms per prediction
- Cost: cheap, any server has a CPU
- Scaling: add more CPU workers (uvicorn --workers 8)
- Best for: < 100 requests/second, models under 500MB

GPU inference:
- Required for large models (BERT, GPT, image models)
- Latency: 1-10ms per prediction (much faster per inference)
- Cost: expensive (GPU instances cost 5-10x CPU instances)
- Scaling: batch multiple requests into one GPU call
- Best for: high throughput, large models, latency-sensitive

For most DBA use cases (alert classification), CPU is sufficient. A keyword classifier on CPU handles thousands of requests per second. Even a DistilBERT model runs at 50-100ms on CPU, which is fine for alerts.

**Single server vs distributed:**

Single server (1 worker):
- Simplest to deploy and debug
- Good for: development, low traffic (< 10 requests/second)
- Risk: single point of failure

Single server (multiple workers):
- uvicorn --workers 4 runs 4 processes
- Good for: medium traffic (10-100 requests/second)
- Risk: still one machine

Multiple servers (load balanced):
- 2+ containers behind a load balancer
- Good for: high availability, 100+ requests/second
- Enables rolling deployments and zero-downtime updates

Auto-scaling:
- Kubernetes HPA (Horizontal Pod Autoscaler)
- Scale based on CPU usage, request rate, or queue depth
- Good for: variable traffic patterns

Start simple (single server + multiple workers), add complexity only when metrics show you need it.

**DBA parallel:** This is the same decision as "single PostgreSQL server vs primary-standby vs multi-node cluster." Start with one server, add replicas for read scaling and HA, add more nodes only when justified by traffic.
