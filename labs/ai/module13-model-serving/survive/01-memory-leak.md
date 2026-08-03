# Survive 01: Memory Leak in Model Server

Your alert classifier API has been running for 5 days. It started using 200MB of memory. Now it's at 3.8GB and climbing. The server is about to run out of memory and crash - taking all prediction traffic with it.

---

## The Disaster

On your **Mac terminal**, run the injection script:

```bash
python3 << 'PYEOF'
import json
import time
from datetime import datetime, timedelta

print("""
SCENARIO: Memory Leak in Model Server

Your model server has been running for 5 days.
Memory usage is climbing steadily:

  Day 1:  200 MB (normal - model loaded)
  Day 2:  600 MB
  Day 3: 1.2 GB
  Day 4: 2.4 GB
  Day 5: 3.8 GB (now) <- server has 4GB, about to crash

The API is still responding, but latency is increasing
as the system starts swapping to disk.

Your job: find the leak and fix it.
""")

# Simulate the leaky server
class LeakyModelServer:
    """Model server with a memory leak."""

    def __init__(self):
        self.model_version = "v3"
        self.prediction_cache = {}
        # BUG: predictions are cached forever, never evicted
        # Every unique request adds to the cache
        # After millions of requests, this eats all memory

        self.request_log = []
        # BUG: all requests logged in memory (never flushed to disk)
        # Each log entry is ~500 bytes
        # 1M requests = 500MB of in-memory logs

    def predict(self, message):
        """Classify with (broken) caching."""
        # Check cache
        cache_key = message.lower().strip()

        if cache_key in self.prediction_cache:
            result = self.prediction_cache[cache_key]
        else:
            # Classify
            msg = message.lower()
            if "cpu" in msg:
                result = {"category": "performance", "confidence": 0.9}
            elif "disk" in msg:
                result = {"category": "storage", "confidence": 0.85}
            else:
                result = {"category": "unknown", "confidence": 0.3}

            # Cache the result (LEAK: never evicted!)
            self.prediction_cache[cache_key] = result

        # Log the request (LEAK: never flushed!)
        self.request_log.append({
            "message": message,
            "result": result,
            "timestamp": datetime.now().isoformat(),
        })

        return result

# Simulate 5 days of traffic
server = LeakyModelServer()

# Generate diverse messages (each unique message = new cache entry)
import random
random.seed(42)

components = ["CPU", "Disk", "Memory", "Network", "IO"]
metrics = ["usage", "latency", "errors", "throughput", "saturation"]
servers = [f"server-{i}" for i in range(100)]
values = [f"{random.randint(50,99)}%" for _ in range(100)]

print("Simulating 5 days of traffic...")
for i in range(50000):
    msg = f"{random.choice(components)} {random.choice(metrics)} at {random.choice(values)} on {random.choice(servers)}"
    server.predict(msg)

print(f"\nAfter 50,000 requests:")
print(f"  Cache entries: {len(server.prediction_cache):,}")
print(f"  Log entries: {len(server.request_log):,}")

# Estimate memory
import sys
cache_size = sys.getsizeof(server.prediction_cache)
log_size = sys.getsizeof(server.request_log)
print(f"  Cache dict size: {cache_size / 1024 / 1024:.1f} MB (just the dict, not values)")
print(f"  Log list size: {log_size / 1024 / 1024:.1f} MB (just the list, not entries)")
print(f"\n  In production with millions of requests, this would be gigabytes")

print("""
Symptoms:
  1. Memory usage climbs steadily (never goes down)
  2. Latency increases as system starts swapping
  3. Eventually: OOM kill or server crash

Where to look:
  1. In-memory caches with no eviction policy
  2. In-memory logs/buffers that never flush
  3. Objects that grow without bound
""")
PYEOF
```

---

## Investigate

On your **Mac terminal**, check the evidence:

```bash
python3 << 'PYEOF'
import sys

print("Investigation: Finding the Memory Leak")
print("=" * 55)

print("""
Step 1: Check what's consuming memory.

In a real server, you'd use:
  - /proc/{pid}/status  (Linux: VmRSS shows resident memory)
  - psutil.Process().memory_info()  (Python memory usage)
  - tracemalloc (Python's built-in memory profiler)
  - objgraph.most_common_types() (count objects by type)
""")

# Simulate tracemalloc output
print("Simulated tracemalloc top allocations:")
print("-" * 50)
print("  #1: model_server.py:45  (prediction_cache dict)")
print("      Size: 2.1 GB, Count: 4,200,000 entries")
print("  #2: model_server.py:52  (request_log list)")
print("      Size: 1.5 GB, Count: 12,000,000 entries")
print("  #3: model_server.py:12  (model weights)")
print("      Size: 200 MB, Count: 1 (this is normal)")

print("""
ROOT CAUSE: Two leaks

Leak 1: prediction_cache (dict)
  - Every unique message creates a new cache entry
  - Cache grows without bound
  - With millions of unique messages, cache eats gigabytes
  - FIX: use an LRU cache with a max size

Leak 2: request_log (list)
  - Every request appends to an in-memory list
  - List is never flushed to disk or trimmed
  - FIX: write logs to file/database, don't keep in memory

DBA analogy:
  Leak 1 is like shared_buffers growing beyond its limit (impossible in PG,
    but imagine if it could). Fixed by setting a max size.
  Leak 2 is like the WAL never being archived - files accumulate forever.
    Fixed by archiving (flushing to disk) and removing old entries.
""")
PYEOF
```

---

## The Fix

On your **Mac terminal**, run the fix:

```bash
python3 << 'PYEOF'
import json
import time
import sys
from datetime import datetime
from collections import OrderedDict

print("""
FIX: Bounded caches and log flushing.

Leak 1 Fix: LRU cache with max size
  - Keep only the N most recently used entries
  - When full, evict the least recently used entry
  - Python has functools.lru_cache, or use OrderedDict

Leak 2 Fix: Flush logs periodically
  - Write logs to file every N entries or every M seconds
  - Clear the in-memory buffer after flushing
  - Keep only recent logs in memory for quick access
""")

class LRUCache:
    """Least Recently Used cache with a max size."""

    def __init__(self, max_size=1000):
        self.max_size = max_size
        self.cache = OrderedDict()
        # OrderedDict remembers insertion order
        # We can move items to the end when accessed (most recently used)
        self.hits = 0
        self.misses = 0

    def get(self, key):
        """Get an item, marking it as recently used."""
        if key in self.cache:
            self.cache.move_to_end(key)
            # move_to_end() marks this as most recently used
            self.hits += 1
            return self.cache[key]
        self.misses += 1
        return None

    def put(self, key, value):
        """Add an item, evicting oldest if full."""
        if key in self.cache:
            self.cache.move_to_end(key)
        else:
            if len(self.cache) >= self.max_size:
                self.cache.popitem(last=False)
                # popitem(last=False) removes the OLDEST item (least recently used)
        self.cache[key] = value

    def stats(self):
        total = self.hits + self.misses
        hit_rate = self.hits / total * 100 if total > 0 else 0
        return {
            "size": len(self.cache),
            "max_size": self.max_size,
            "hits": self.hits,
            "misses": self.misses,
            "hit_rate": round(hit_rate, 1),
        }

class BufferedLogger:
    """Log to file with in-memory buffer."""

    def __init__(self, log_file, buffer_size=100):
        self.log_file = log_file
        self.buffer_size = buffer_size
        self.buffer = []
        self.total_flushed = 0

    def log(self, entry):
        """Add a log entry. Flush to disk if buffer is full."""
        self.buffer.append(entry)
        if len(self.buffer) >= self.buffer_size:
            self.flush()

    def flush(self):
        """Write buffer to disk and clear it."""
        if not self.buffer:
            return
        with open(self.log_file, "a") as f:
            for entry in self.buffer:
                f.write(json.dumps(entry) + "\n")
        self.total_flushed += len(self.buffer)
        self.buffer.clear()
        # .clear() empties the list, freeing memory

    def stats(self):
        return {
            "buffer_size": len(self.buffer),
            "max_buffer": self.buffer_size,
            "total_flushed": self.total_flushed,
        }

class FixedModelServer:
    """Model server with bounded memory usage."""

    def __init__(self):
        self.model_version = "v3"
        self.cache = LRUCache(max_size=1000)
        # Max 1000 cached predictions - old ones get evicted
        self.logger = BufferedLogger("/tmp/model_requests.log", buffer_size=100)
        # Logs flush to disk every 100 entries

    def predict(self, message):
        cache_key = message.lower().strip()

        # Check cache
        result = self.cache.get(cache_key)
        if result is None:
            # Classify
            msg = message.lower()
            if "cpu" in msg:
                result = {"category": "performance", "confidence": 0.9}
            elif "disk" in msg:
                result = {"category": "storage", "confidence": 0.85}
            else:
                result = {"category": "unknown", "confidence": 0.3}
            self.cache.put(cache_key, result)

        # Log (buffered, flushes to disk)
        self.logger.log({
            "message": message[:100],
            "result": result,
            "timestamp": datetime.now().isoformat(),
        })

        return result

# Test: run the same 50,000 requests
import random
random.seed(42)

server = FixedModelServer()

components = ["CPU", "Disk", "Memory", "Network", "IO"]
metrics = ["usage", "latency", "errors", "throughput", "saturation"]
servers_list = [f"server-{i}" for i in range(100)]
values = [f"{random.randint(50,99)}%" for _ in range(100)]

# Clear log file
open("/tmp/model_requests.log", "w").close()

print("Running 50,000 requests with FIXED server:")
print("-" * 50)

for i in range(50000):
    msg = f"{random.choice(components)} {random.choice(metrics)} at {random.choice(values)} on {random.choice(servers_list)}"
    server.predict(msg)

server.logger.flush()  # flush remaining buffer

print(f"\nAfter 50,000 requests:")
print(f"\nCache stats:")
cache_stats = server.cache.stats()
for k, v in cache_stats.items():
    print(f"  {k}: {v}")

print(f"\nLogger stats:")
log_stats = server.logger.stats()
for k, v in log_stats.items():
    print(f"  {k}: {v}")

print(f"\n  Cache stays at max {server.cache.max_size} entries (bounded)")
print(f"  Logs flushed to disk ({server.logger.total_flushed:,} entries)")
print(f"  In-memory buffer: max {server.logger.buffer_size} entries (bounded)")
print(f"  Memory usage: STABLE (doesn't grow with traffic)")

print("""
Prevention checklist:
  1. BOUND all in-memory data structures (max size)
  2. FLUSH logs/buffers to disk periodically
  3. USE LRU eviction for caches (keep hot data, evict cold)
  4. MONITOR memory usage over time (should be flat, not climbing)
  5. SET memory limits (Docker: --memory 2g, K8s: resources.limits.memory)
  6. TEST with sustained traffic (not just 100 requests)

  DBA parallel:
    - shared_buffers has a fixed size (bounded cache)
    - WAL is archived and removed (log flushing)
    - work_mem limits per-query memory (bounded operations)
    - pg_stat_statements has max entries (bounded tracking)
""")
PYEOF
```

---

## What You Learned

| Problem | Why It's Dangerous | Fix |
|---------|--------------------|-----|
| Unbounded cache | Grows until OOM | LRU cache with max_size |
| In-memory logs | Grows with every request | Flush to disk, bounded buffer |
| No eviction policy | Old data never freed | LRU - evict least recently used |
| No memory monitoring | Leak goes unnoticed for days | Track memory over time, alert on growth |
| No memory limits | Process takes all available RAM | Docker --memory or K8s limits |
