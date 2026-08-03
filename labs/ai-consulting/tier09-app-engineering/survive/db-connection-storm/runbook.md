# SURVIVE Runbook: Database Connection Storm Under Load

**Scenario:** under traffic, the app starts returning errors and the database logs "too many clients already." A recent change replaced the connection **pool** with a naive "open a connection per request and never close it" pattern. Every request leaks a connection; a burst of traffic exhausts PostgreSQL.

**Your job:** confirm the leak, restore pooling, and prove the app now survives the same burst without exhausting connections.

**Where you are:** the **lab server** (CentOS Stream 9), as **ec2-user**, with Project 9 in `~/project9`.

---

## Step 1: See the symptom

On your **lab server**, as **ec2-user**:

```bash
cd ~/project9
```

Load your environment so `psql` works:

```bash
set -a; . ./.env; set +a
```

Count how many connections the app has open to the database right now:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database();"
```

Expected output (yours will differ - the number is high and climbing):

```
 count
-------
    42
(1 row)
```

Dozens of open connections for an app that should need a handful. That is the leak. In production this is where new requests would start failing with "too many clients."

---

## Step 2: Check what the app thinks its pool looks like

Ask the running app about its pool via `/metrics`:

Still on the **lab server**, as **ec2-user**:

```bash
curl -s http://127.0.0.1:8000/metrics
```

Expected output (yours will differ - note the pool):

```
{"ask_count":40,"avg_latency_ms":3.1,"max_latency_ms":22,"ingest_queue":{"queued":0,"processing":0,"done":0,"failed":0},"db_pool":{"min":0,"max":0,"initialized":false,"leaked":40}}
```

`"initialized":false` and a growing `"leaked"` count. The pool is not being used at all - every request made its own connection and never gave it back.

---

## Step 3: Find the bad code

Look at how `get_conn` is implemented.

Still on the **lab server**, as **ec2-user**:

```bash
grep -n "_LEAKED\|def get_conn\|putconn" db.py
```

Expected output:

```
28:_LEAKED = []  # keep references so connections are NOT garbage-collected/closed
32:def get_conn():
36:    _LEAKED.append(conn)  # leak on purpose: never closed, never reused
```

There is no `putconn` and there is a `_LEAKED` list holding connections open forever. This is the smoking gun.

---

## Step 4: Restore the pooled implementation

You kept a backup of the correct file when the fault was injected. Restore it.

Still on the **lab server**, as **ec2-user**:

```bash
cp db.py.orig db.py
```

Confirm the good version is back (it uses a real pool and always returns connections):

```bash
grep -n "ThreadedConnectionPool\|putconn" db.py
```

Expected output (yours will differ):

```
36:_POOL: pool.ThreadedConnectionPool | None = None
72:        _POOL.putconn(conn)
```

`putconn` in a `finally` block is the key: every borrowed connection is returned to the pool no matter what, so connections are reused instead of leaked.

---

## Step 5: Kill the leaked connections and restart

The old process still holds all those leaked connections. Restart the API to drop them and load the fixed code.

Still on the **lab server**, as **ec2-user**, stop the app:

```bash
pkill -f "uvicorn app:app"
```

Give PostgreSQL a moment to clean up the dropped connections:

```bash
sleep 2
```

Start the app again in the background:

```bash
nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
```

Wait for it to come up:

```bash
sleep 3
```

---

## Step 6: Prove it survives the same burst

Fire the same burst of concurrent requests that broke it before.

Still on the **lab server**, as **ec2-user**:

```bash
for i in $(seq 1 40); do curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer token-admin" -H "Content-Type: application/json" -d '{"query":"backup"}' http://127.0.0.1:8000/ask & done; wait
```

This loop launches 40 requests in parallel (`&`) and `wait`s for all of them. Expected output (yours will differ - all `200`):

```
200
200
200
...
200
```

Every request succeeded. Now check the connection count again:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database();"
```

Expected output (yours will differ - small and stable):

```
 count
-------
     6
(1 row)
```

A handful of connections handled 40 concurrent requests, because the pool reuses them. That is the whole point of pooling.

---

## Step 7: Validate

Run the checker:

```bash
bash ~/project9/survive/db-connection-storm/validate.sh
```

Expected output:

```
OK: db.py no longer contains the connection leak
OK: /metrics reports an initialized connection pool
Firing 40 concurrent requests...
OK: all 40 concurrent requests returned 200
OK: open backend connections bounded (6)
PASS: pooling restored; app survives the connection storm.
```

---

## What you learned

- **Never open a connection per request.** Connecting is expensive (TCP + auth) and unbounded. A pool keeps a small set of connections open and reuses them, and its `maxconn` is a hard ceiling that protects the database from being overwhelmed.
- **Always return the connection - in a `finally`.** The leak here was a missing `putconn`. A borrowed resource that is not returned on every path (including errors) is the classic leak. The context-manager `finally` guarantees it.
- **Size the pool below the database limit.** `maxconn` across all app instances must stay under PostgreSQL's `max_connections`. With N app instances of pool size P, you need N*P plus headroom under the server limit. Consider a server-side pooler like PgBouncer when N grows.
- **Watch `pg_stat_activity`.** A steadily rising connection count with steady traffic is a leak in progress. Alert on it before it hits the ceiling.
- **Fail predictably under overload.** With a bounded pool, extra requests wait briefly instead of crashing the database. Bounded degradation beats a total outage.

Prof. Happy (SUTA Labs)
