# BUILD: Project 1 - Support Ticket Summarizer

**Tier 1 - the capstone build.** You will build a small Python service that reads customer-support tickets from PostgreSQL, cleans and categorizes them, exposes a summary through a FastAPI endpoint, runs its own tests, and ships in a Docker container.

**Validated on:** CentOS Stream 9, PostgreSQL 13.23, Python 3.12.13, Docker 29.6.2, on 2026-07-23. All output shown is real (truncated where long).

**Prerequisite:** you finished the Phase 0 environment setup - Python 3.12, Docker, and PostgreSQL with the `labuser`/`labdb`/`labpass` database are all working.

The project files live in `project1-support-summary/` next to this guide: `app.py`, `test_app.py`, `seed.sql`, `requirements.txt`, `Dockerfile`.

---

## Step 1: Put the files on your server

On your **lab server**, as **ec2-user**, create a project folder and place the five files in it (copy them from this repo, or write them with `vi`):

```bash
mkdir -p ~/project1
```

You should have: `app.py`, `test_app.py`, `seed.sql`, `requirements.txt`, `Dockerfile`.

---

## Step 2: Seed the database

Load the sample tickets into `labdb`.

On your **lab server**, as **ec2-user**:

```bash
cd ~/project1
```

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -f seed.sql
```

Expected output:

```
CREATE TABLE
INSERT 0 10
```

`INSERT 0 10` means 10 sample tickets were loaded.

---

## Step 3: Create a virtual environment and install requirements

Still on your **lab server**, as **ec2-user**, in `~/project1`:

```bash
python3.12 -m venv .venv
```

```bash
source .venv/bin/activate
```

```bash
pip install -r requirements.txt
```

Confirm the key packages are present:

```bash
pip list | grep -Ei "fastapi|uvicorn|psycopg2|pytest|httpx"
```

Expected output (yours will differ):

```
fastapi           0.115.0
httpx             0.27.2
psycopg2-binary   2.9.9
pytest            8.3.2
uvicorn           0.30.6
```

---

## Step 4: Run the tests

The tests check the categorization rules without needing the database, so they run fast.

Still in the activated environment:

```bash
python -m pytest -q
```

Expected output (yours will differ):

```
.....                                                                    [100%]
5 passed in 0.34s
```

Five dots, five passed. If a test fails, fix the code before moving on - never advance on a red test.

---

## Step 5: Start the API and call it

Start the web server in the background:

```bash
nohup uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
```

`uvicorn` is the server. `app:app` means "the `app` object inside `app.py`". Give it a couple of seconds, then check health:

```bash
curl -s http://127.0.0.1:8000/health
```

Expected output:

```
{"status":"ok"}
```

Now get the summary:

```bash
curl -s http://127.0.0.1:8000/summary
```

Expected output (yours will differ):

```
{"total":10,"by_category":{"billing":3,"auth":2,"bug":2,"feature":1,"performance":1,"uncategorized":1}}
```

Notice the ticket "How do I add a user" had no category and matched no keyword, so it correctly became `uncategorized`. That is the cleaning-and-categorizing logic working.

Stop the server when done:

```bash
pkill -f "uvicorn app:app"
```

---

## Step 6: Package and run in Docker

A container makes the app run the same anywhere. Build the image.

On your **lab server**, as **ec2-user**, in `~/project1`:

```bash
docker build -t support-summary .
```

Expected output (yours will differ, truncated):

```
 => naming to docker.io/library/support-summary:latest
 => unpacking to docker.io/library/support-summary:latest
DONE 2.7s
```

Run the container, passing the database settings as environment variables (never baked into the image):

```bash
docker run -d --name support-summary --network host \
  -e DB_HOST=127.0.0.1 -e DB_USER=labuser -e DB_PASSWORD=labpass -e DB_NAME=labdb \
  support-summary
```

`--network host` lets the container reach PostgreSQL on the host's `127.0.0.1`. `-d` runs it in the background. Give it a few seconds, then:

```bash
curl -s http://127.0.0.1:8000/summary
```

Expected output (yours will differ):

```
{"total":10,"by_category":{"billing":3,"auth":2,"bug":2,"feature":1,"performance":1,"uncategorized":1}}
```

Same answer as before, now served from inside a container. Clean up:

```bash
docker rm -f support-summary
```

---

## What you just built

- A Python service that reads from PostgreSQL, cleans blank records, and categorizes tickets with keyword rules.
- A FastAPI API with a `/health` liveness check and a `/summary` endpoint.
- A passing test suite.
- A Docker image that runs the same service anywhere, configured entirely by environment variables.

## Notes on good practice (why the code looks the way it does)

- **Secrets come from environment variables**, never hardcoded - see the `os.environ.get` calls in `app.py`.
- **Errors are not swallowed**: when the database is unreachable the API returns a clear `503` with the reason, instead of crashing or hiding it. You prove this in the SURVIVE scenario.
- **Tests run without the database** so they are fast and deterministic in CI.

Next: the USE exercises push this further (new schema, pagination, a webhook), and the SURVIVE scenarios break it on purpose so you learn to recover.
