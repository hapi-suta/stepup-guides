# INTERVIEW: DBA Automation Interview Questions

**Module:** 00c - Python DBA Automation
**Type:** Interview Preparation
**Time:** 30-45 minutes to study

These are questions you will face (or ask) in interviews for Senior DBA, Database Reliability Engineer, or Platform Engineer roles. Each includes what the interviewer is really looking for, a strong answer, and a weak answer.

---

## Question 1: How do you prevent SQL injection in Python scripts that manage databases?

**What the interviewer wants:**
They want to know if you understand the difference between string interpolation and parameterized queries. They want to hear you mention psycopg2's `%s` placeholders specifically. Bonus points if you mention `psycopg2.sql.Identifier()` for DDL statements. They are also checking if you take security seriously even for "internal tools."

**Strong answer:**

"I never use f-strings, string concatenation, or Python's % operator to build SQL. For data values, I use psycopg2's parameterized queries with `%s` placeholders - the parameters are passed as a tuple in the second argument to `cursor.execute()`. This ensures the database treats the input as a value, never as SQL code.

For identifiers like table names or role names in DDL statements, `%s` placeholders do not work because PostgreSQL does not allow parameterized identifiers. For those, I use `psycopg2.sql.Identifier()` from the `psycopg2.sql` module, which properly quotes the identifier.

On top of parameterized queries, I add input validation as defense-in-depth - regex checks to ensure usernames or database names match expected patterns before they ever hit the database. Even for scripts only DBAs run, because a typo or a weird name with special characters can cause the same damage as a deliberate attack."

**Weak answer:**

"I make sure to escape single quotes before putting them in the query string. I also validate that the input does not contain semicolons or SQL keywords like DROP."

Why it is weak: Manual escaping is error-prone and incomplete. Blacklisting SQL keywords is a cat-and-mouse game that attackers always win. The correct approach is parameterized queries where the database driver handles safety, not the developer.

---

## Question 2: Walk me through how you would automate a daily health check for 50 PostgreSQL databases.

**What the interviewer wants:**
They want to see system design thinking. Can you handle multiple databases? Do you think about credentials, failure modes, alerting, and reporting? They also want to see if you over-engineer or keep it practical.

**Strong answer:**

"I would build a Python script with these components:

First, a config file or database table listing all 50 servers with connection details - host, port, database name, and a reference to credentials stored in a secrets manager or environment variables. Never hardcoded.

The script would have modular check functions - connection count vs max_connections, database sizes, replication lag, long-running queries, and dead tuple ratios. Each returns a status (OK, WARNING, CRITICAL) and details.

For execution, I would iterate through servers with a timeout on each connection attempt - if one server is down, it should not block the other 49. I would use a single connection per server, run all checks, then close it. Error handling per-server so one failure does not crash the whole run.

Output goes two places: a structured log file with timestamps for trending, and an alert channel (email, Slack, PagerDuty) for WARNING and CRITICAL results only. Exit code follows the Nagios convention - 0 for OK, 1 for WARNING, 2 for CRITICAL - so it integrates with any monitoring system.

Scheduling via cron at 6 AM and 6 PM, with a healthcheck endpoint or log rotation so I know the script itself is running. I would start with sequential checks and only parallelize if the 50-server run takes more than 5 minutes."

**Weak answer:**

"I would write a bash script with psql that loops through the servers and sends an email if something is wrong."

Why it is weak: No mention of error handling, credential management, structured output, or what happens when one server is unreachable. Bash is fine for simple tasks but becomes unmaintainable for 50 servers with multiple checks.

---

## Question 3: What is the difference between fetchall() and using a cursor as an iterator? When does it matter?

**What the interviewer wants:**
They are testing whether you understand memory management when dealing with large result sets. This separates developers who have worked with real production data from those who only query small tables.

**Strong answer:**

"`fetchall()` loads the entire result set into Python's memory as a list of tuples. If the query returns 10 million rows, all 10 million rows sit in RAM at once. For queries against `pg_stat_activity` or `pg_database` where you get a few hundred rows at most, this is fine and convenient.

When you iterate directly over the cursor with `for row in cur:`, psycopg2 still fetches all rows from the server by default - it is not truly lazy. But it yields them one at a time from an internal buffer, so your Python code processes them incrementally. This is slightly better for memory if you do not need all rows at once.

For truly large result sets - like dumping a table for ETL - I would use a named server-side cursor: `cur = conn.cursor(name='my_cursor')`. This tells PostgreSQL to hold the result set server-side and only send rows as Python fetches them. Combined with `fetchmany(1000)`, you process in batches of 1000 without loading millions of rows into memory.

It matters when your result set exceeds available RAM. I have seen Python scripts OOM-killed because they did `fetchall()` on a 50-million-row table during a data migration."

**Weak answer:**

"fetchall() gets all the rows and the iterator gets them one at a time. I always use fetchall() because it is simpler."

Why it is weak: Does not mention memory implications, does not know about server-side cursors, and the "always use fetchall()" approach shows no experience with large datasets.

---

## Question 4: How do you handle credentials in automation scripts?

**What the interviewer wants:**
This is a security question. They want to hear about environment variables, secrets managers, and `.pgpass` files. They are checking if you would ever commit a password to Git.

**Strong answer:**

"Multiple layers depending on the environment.

For local development and simple scripts, I use environment variables - `PGHOST`, `PGUSER`, `PGPASSWORD`, etc. psycopg2 reads these automatically. The variables are set in a `.env` file that is in `.gitignore` and never committed.

For production servers, I use the PostgreSQL `.pgpass` file with strict permissions (0600). psycopg2 and libpq read it automatically - the script does not need to handle the password at all. The connection just works.

For cloud environments, I use the cloud provider's secrets manager - AWS Secrets Manager, HashiCorp Vault, or similar. The script fetches credentials at startup using an IAM role, so no secrets exist on disk at all.

For CI/CD pipelines, credentials go in the pipeline's secret storage (GitHub Actions secrets, GitLab CI variables) and are injected as environment variables at runtime.

I never hardcode credentials in source code, never commit `.env` files, and rotate credentials on a schedule. Connection strings in logs are scrubbed - I log the host and database name but never the password."

**Weak answer:**

"I put the password in a config file next to the script. Only DBAs have access to the server so it is safe."

Why it is weak: Config files get committed to Git by accident, copied to shared drives, or left on decommissioned servers. "Only DBAs have access" is not a security control - it is a hope.

---

## Question 5: You need to kill all queries running longer than 30 minutes - write the Python approach.

**What the interviewer wants:**
They want to see you write safe, production-ready code - not just a one-liner. They are checking for: parameterized queries, dry-run mode, logging, excluding important system queries, and error handling.

**Strong answer:**

```python
import os
import logging
import psycopg2

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger('query_killer')

def kill_long_queries(max_minutes: int = 30, dry_run: bool = True) -> int:
    """Terminate queries running longer than max_minutes.

    Returns count of terminated queries.
    """
    conn = psycopg2.connect(
        host=os.environ.get('PGHOST', 'localhost'),
        dbname=os.environ.get('PGDATABASE', 'postgres'),
        user=os.environ.get('PGUSER', 'postgres'),
        password=os.environ.get('PGPASSWORD', '')
    )
    conn.autocommit = True  # pg_terminate_backend needs autocommit
    terminated = 0

    try:
        with conn.cursor() as cur:
            # Find long-running queries, excluding our own session and system processes
            cur.execute("""
                SELECT pid, usename,
                       EXTRACT(EPOCH FROM age(clock_timestamp(), query_start))::int / 60 as minutes,
                       left(query, 100) as query_preview,
                       client_addr
                FROM pg_stat_activity
                WHERE state = 'active'
                  AND pid != pg_backend_pid()
                  AND backend_type = 'client backend'
                  AND EXTRACT(EPOCH FROM age(clock_timestamp(), query_start)) > %s
                ORDER BY query_start
            """, (max_minutes * 60,))

            stale_queries = cur.fetchall()

            if not stale_queries:
                logger.info(f"No queries running longer than {max_minutes} minutes")
                return 0

            for pid, user, minutes, query, addr in stale_queries:
                logger.warning(
                    f"Long query: PID={pid} user={user} addr={addr} "
                    f"running={minutes}m query={query}"
                )

                if not dry_run:
                    cur.execute("SELECT pg_terminate_backend(%s)", (pid,))
                    success = cur.fetchone()[0]
                    if success:
                        logger.info(f"Terminated PID {pid}")
                        terminated += 1
                    else:
                        logger.error(f"Failed to terminate PID {pid}")
                else:
                    logger.info(f"DRY RUN: Would terminate PID {pid}")

    finally:
        conn.close()

    logger.info(f"Summary: {len(stale_queries)} found, {terminated} terminated")
    return terminated
```

"Key design decisions: autocommit is required because `pg_terminate_backend` should take effect immediately. I exclude my own PID and system backends. I use parameterized queries for the threshold. The dry_run flag defaults to True so you cannot accidentally kill queries. I log every action with PID, user, client address, and a query preview for post-incident review. And I always close the connection in a finally block."

**Weak answer:**

```python
import psycopg2
conn = psycopg2.connect(dbname='postgres', user='postgres')
cur = conn.cursor()
cur.execute("""
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE query_start < now() - interval '30 minutes'
""")
print(f"Killed {cur.rowcount} queries")
```

Why it is weak: No dry-run mode - it kills immediately with no confirmation. No logging - you have no record of what was killed. Does not filter by state (kills idle connections too). Does not exclude system processes. Does not exclude its own connection. No error handling. Hardcoded credentials and connection parameters.

---

## Study Tips

1. **Practice writing these scripts from memory.** The interviewer may ask you to live-code on a whiteboard or shared screen.
2. **Know the pg_stat views cold.** `pg_stat_activity`, `pg_stat_replication`, `pg_stat_user_tables`, `pg_stat_bgwriter` - know what columns each has and what they mean.
3. **Always mention security first.** Parameterized queries, credential management, and dry-run modes show maturity.
4. **Show production thinking.** Error handling, logging, graceful degradation, and "what happens at 3 AM" scenarios.
5. **Use DBA terminology naturally.** You are a DBA learning Python, not a Python developer learning databases. Your database knowledge is the strength - show that the Python is just a tool to automate what you already know.
