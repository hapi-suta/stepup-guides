# SURVIVE Runbook: Embedding Version Change (Silent Retrieval Degradation)

**Scenario:** the stored chunk vectors were produced by one embedding model, but query embeddings are now produced by a *different* model version. Comparing vectors from two different models is meaningless, so retrieval quietly returns irrelevant chunks. **Nothing errors.** The service is up, latency is normal, and every answer is subtly wrong or a refusal. This is the most dangerous kind of failure because it is invisible until someone notices the answers got bad.

**The rule you are enforcing:** query vectors and stored vectors must come from the **same embedding model**. Whenever the embedding model changes, you must **re-index** (re-embed every chunk) with the new model. Storing the model name with each vector is what lets you *detect* the mismatch.

You are on the **lab server** (CentOS Stream 9), as **ec2-user**, with Project 7 in `~/project7`, DB seeded and corpus ingested.

---

## Step 1: Notice the symptom

On your **lab server**, as **ec2-user**:

```bash
cd ~/project7
```

Ask a question you know the corpus can answer:

```bash
python3 -c "import rag; c=rag.db_conn(); print(rag.answer(c,'What is the remote work probation period?',user_level=1)['answer'])"
```

Expected output (the symptom - a refusal or wrong answer where there should be a clear one):

```
I don't have that information.
```

The corpus clearly contains the probation period, yet the system cannot find it. That points at retrieval, not the LLM.

---

## Step 2: Confirm retrieval is returning junk

Look at what retrieval actually returns for that question:

```bash
python3 -c "import rag; c=rag.db_conn(); [print(round(r['distance'],3), r['source']) for r in rag.retrieve(c,'remote work probation period',user_level=1,k=3,max_distance=2.0)]"
```

Expected output (junk - high distances, wrong sources near the top):

```
1.42 fr-securite.txt
1.55 en-expense-policy.txt
1.61 fr-conges.txt
```

The distances are large (poor matches) and the expected `en-remote-work.txt` is not near the top. Retrieval is broken.

---

## Step 3: Detect the root cause - a model mismatch

Because you stored the embedding model name with each chunk, you can detect the mismatch directly. Compare what the chunks were embedded with against what the code embeds with now.

```bash
python3 -c "import rag; c=rag.db_conn(); cur=c.cursor(); cur.execute('SELECT DISTINCT embed_model FROM chunks'); print('stored:', [r[0] for r in cur.fetchall()], 'current:', rag.embed_model_name())"
```

Expected output (the mismatch):

```
stored: ['legacy-v0'] current: all-MiniLM-L6-v2
```

(On a box without the sentence-transformers model, `current` will be `hashing-v1` - either way, it does not match `legacy-v0`.)

The stored vectors were made with `legacy-v0`; the code now embeds with a different model. That is the root cause: you cannot compare vectors across models.

---

## Step 4: Re-index (re-embed every chunk with the current model)

The fix is to re-run ingestion, which re-embeds every chunk with the current model and re-stamps the correct `embed_model`.

Still on the **lab server**, as **ec2-user**, in `~/project7`:

```bash
python3 ingest.py
```

Expected output (yours will differ):

```
[ingest] embedding model: all-MiniLM-L6-v2
[ingest] loaded 6 documents, 14 chunks (0 duplicate chunks skipped)
```

`ingest.py` clears and reloads, so every chunk is now embedded with the current model.

---

## Step 5: Verify retrieval is restored

Re-run the question from Step 1:

```bash
python3 -c "import rag; c=rag.db_conn(); print(rag.answer(c,'What is the remote work probation period?',user_level=1)['answer'])"
```

Expected output (fixed - a grounded, cited answer):

```
[MOCK] Based on the retrieved context: Remote Work Policy Eligibility All full-time employees who have completed their probation period of ninety days ... [1]
```

(With a real `ANTHROPIC_API_KEY` set, this is a fluent sentence instead of the `[MOCK]` stitch - either way it now contains "ninety days".)

---

## Step 6: Run the validator

```bash
bash survive/embedding-version-change/validate.sh
```

Expected output (last lines):

```
OK: all chunks embedded with the current model 'all-MiniLM-L6-v2'
OK: retrieval returns the expected document again
PASS: embedding version consistent and retrieval restored.
```

---

## What you learned

- An embedding-model change breaks retrieval **silently** - no error, just worse answers. Monitor answer quality and refusal rate to catch it (a rising refusal rate is a classic tell).
- Storing the model name with each vector turns a silent, invisible failure into a one-line detection.
- The fix is always **re-indexing**: re-embed every chunk with the new model. You cannot mix vectors from two models.
- In production, gate embedding-model upgrades behind a re-index job, and never point a new query model at an index built with an old one.
