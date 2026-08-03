# SURVIVE Runbook: Access-Control Bypass (CRITICAL)

**Scenario:** a change to the retrieval query removed the access-control filter. A low-clearance user (an intern, clearance level 1) can now retrieve chunks from a **RESTRICTED** document - the executive compensation memo. If they ask "what is the CEO salary band?", the system will retrieve the secret document and the LLM will quote it back. This is a **data breach**.

**Why this is the most important scenario in the tier:** enterprises adopt RAG to unlock their private documents. The entire value proposition depends on the system *never* showing a user a document they are not cleared to see. A single missed filter turns your knowledge assistant into a data-exfiltration tool. Getting this right is the difference between a deployable product and a liability.

**The rule you are enforcing:** access control is enforced **in the retrieval SQL query, at the database**. Forbidden rows must never leave the database. You do **not** fetch everything and hide the forbidden results in application code - one missed code path leaks data.

You are on the **lab server** (CentOS Stream 9), as **ec2-user**, with Project 7 in `~/project7`, the database seeded and the corpus ingested.

---

## Step 1: Confirm the leak

On your **lab server**, as **ec2-user**, go to the project directory:

```bash
cd ~/project7
```

Reproduce the breach: ask, as an intern, for the restricted CEO salary. This tiny script uses the real retrieval path.

```bash
python3 -c "import rag; c=rag.db_conn(); [print(r['access_level'], r['source']) for r in rag.retrieve(c,'CEO salary band executive compensation',user_level=1,k=10,max_distance=2.0)]"
```

`python3 -c "..."` runs a one-line Python program. `user_level=1` is the intern's clearance. `max_distance=2.0` disables the relevance gate so we see everything retrieval would consider.

Expected output (the leak - yours will differ slightly):

```
4 en-exec-comp.txt
1 en-remote-work.txt
...
```

The first column is the chunk's `access_level`. Seeing `4 en-exec-comp.txt` returned for a `user_level=1` request is the breach: a restricted (level 4) chunk was retrieved for a level-1 user.

---

## Step 2: Find the bug in the query

The bug is always in the retrieval query. Look at the `WHERE` clause of `retrieve()`.

Still on the **lab server**, as **ec2-user**:

```bash
grep -n "WHERE" rag.py
```

`grep -n` prints matching lines with their line numbers.

Expected output (the bug):

```
142:        WHERE 1 = 1  -- BUG: access_level filter removed
```

`WHERE 1 = 1` matches every row - the access-control condition that should be there is gone. There is also a matching change where `user_level` was removed from the query parameters.

---

## Step 3: Restore the access-control filter

Open `rag.py` with `vi`:

```bash
vi rag.py
```

In `vi`, type `/WHERE 1 = 1` and press Enter to jump to the bug. Press `i` to enter insert mode. Change the line back to:

```
        WHERE c.access_level <= %(user_level)s
```

Then find the parameters line (search with `/params: dict`). It currently reads:

```
    params: dict[str, Any] = {"qvec": qvec}  # BUG: user_level no longer applied
```

Change it back to:

```
    params: dict[str, Any] = {"qvec": qvec, "user_level": user_level}
```

Press `Esc`, then type `:wq` and press Enter to save and quit.

The fix puts the security filter back **in the SQL**, so restricted rows are never returned by the database in the first place.

---

## Step 4: Verify the leak is closed

Re-run the exact reproduction from Step 1:

```bash
python3 -c "import rag; c=rag.db_conn(); [print(r['access_level'], r['source']) for r in rag.retrieve(c,'CEO salary band executive compensation',user_level=1,k=10,max_distance=2.0)]"
```

Expected output (fixed - no level-4 rows, no exec-comp):

```
1 en-remote-work.txt
1 en-remote-work.txt
...
```

Every row is now `access_level 1` and the exec-comp document is gone. The intern can no longer reach the restricted document.

Confirm an intern now gets a refusal for the salary question:

```bash
python3 -c "import rag; c=rag.db_conn(); print(rag.answer(c,'What is the CEO salary band?',user_level=1)['answer'])"
```

Expected output:

```
I don't have that information.
```

---

## Step 5: Run the validator

Still on the **lab server**, as **ec2-user**, in `~/project7`:

```bash
bash survive/access-control-bypass/validate.sh
```

Expected output (last lines):

```
OK: access-control filter is present in the SQL
OK: level-1 user cannot retrieve any restricted chunk
OK: level-1 answer does not leak the restricted figure
OK: authorized level-4 user can still retrieve the restricted doc
PASS: access control enforced - low clearance blocked, high clearance allowed.
```

`PASS` on the last line means the breach is closed **and** you did not over-correct (a board member can still see the document they are cleared for).

---

## What you learned

- Access control in RAG belongs **in the retrieval query**, enforced by the database - never as a post-filter in application code.
- A leak is silent: the system keeps "working" and answering, it just answers with data it should never have shown. Only a test or an audit catches it - which is why you write the access-control test (see `test_rag.py`).
- The fix must be *tight but not over-tight*: block the unauthorized user without breaking the authorized one. A good validator checks both directions.

The clean version of `rag.py` is in `rag.py.bak` if you want to compare your fix.
