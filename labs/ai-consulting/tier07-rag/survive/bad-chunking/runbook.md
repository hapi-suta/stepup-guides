# SURVIVE Runbook: Bad Chunking (Irrelevant Chunks Retrieved)

**Scenario:** the index was rebuilt with a broken chunker that splits documents into tiny fixed-size fragments, cutting sentences mid-word. Facts are now split across fragments, so no single chunk cleanly answers a question. Retrieval returns fragments, and answers get vague or wrong. **No error is raised** - the pipeline runs, the results are just bad.

**The rule you are enforcing:** you retrieve *chunks*, so chunk quality caps retrieval quality. Chunks should be coherent passages (a few hundred characters, one idea each), split on natural boundaries, ideally with a little overlap.

You are on the **lab server** (CentOS Stream 9), as **ec2-user**, with Project 7 in `~/project7`, DB seeded and corpus ingested.

---

## Step 1: Notice the symptom

On your **lab server**, as **ec2-user**:

```bash
cd ~/project7
```

Ask a known-answerable question:

```bash
python3 -c "import rag; c=rag.db_conn(); print(rag.answer(c,'What is the remote work probation period?',user_level=1)['answer'])"
```

Expected output (the symptom - a fragmented, unhelpful answer or a refusal):

```
I don't have that information.
```

The corpus contains the answer, yet the system cannot assemble it.

---

## Step 2: Diagnose - look at what got retrieved

The fastest diagnosis in RAG is always: *look at the retrieved chunks.*

```bash
python3 -c "import rag; c=rag.db_conn(); [print(repr(r['chunk_text'][:50])) for r in rag.retrieve(c,'remote work probation period',user_level=1,k=5,max_distance=2.0)]"
```

`repr(...)` shows the raw string so you can see fragmentation clearly.

Expected output (the fragments - tiny, mid-word cuts):

```
'Remote Work Policy Eligibility All full-tim'
'e employees who have completed their proba'
'tion period of ninety days are eligible to'
...
```

The word "probation" is split across two chunks ("proba" + "tion"). No chunk contains the whole fact "probation period of ninety days", so retrieval cannot return a clean answer.

Confirm the chunks are tiny by checking the average length:

```bash
python3 -c "import rag; c=rag.db_conn(); cur=c.cursor(); cur.execute('SELECT count(*), avg(length(chunk_text)) FROM chunks'); n,a=cur.fetchone(); print(f'{n} chunks, avg {a:.0f} chars')"
```

Expected output (the problem - far too small):

```
84 chunks, avg 40 chars
```

40-character chunks are the smoking gun. Good chunks are a few hundred characters.

---

## Step 3: Re-chunk with the correct chunker

The fix is to re-ingest with the proper sentence/paragraph-aware chunker, which is still in `rag.py` (`chunk_text`). A plain re-ingest uses it.

Still on the **lab server**, as **ec2-user**, in `~/project7`:

```bash
python3 ingest.py
```

Expected output (yours will differ):

```
[ingest] embedding model: all-MiniLM-L6-v2
[ingest] loaded 6 documents, 14 chunks (0 duplicate chunks skipped)
```

Notice the chunk count dropped from ~84 tiny fragments to ~14 coherent chunks.

---

## Step 4: Verify retrieval recovered

Re-run the question from Step 1:

```bash
python3 -c "import rag; c=rag.db_conn(); print(rag.answer(c,'What is the remote work probation period?',user_level=1)['answer'])"
```

Expected output (fixed - a grounded, cited answer containing the fact):

```
[MOCK] Based on the retrieved context: Remote Work Policy Eligibility All full-time employees who have completed their probation period of ninety days ... [1]
```

And confirm the top match is now a good (low) distance:

```bash
python3 -c "import rag; c=rag.db_conn(); r=rag.retrieve(c,'remote work probation period',user_level=1,k=1)[0]; print(round(r['distance'],3), r['source'])"
```

Expected output (a good match):

```
0.31 en-remote-work.txt
```

---

## Step 5: Run the validator

```bash
bash survive/bad-chunking/validate.sh
```

Expected output (last lines):

```
OK: average chunk length is 4xx chars (not fragmented)
OK: retrieval recovered (top=en-remote-work.txt, distance=0.3xx)
PASS: index re-chunked sensibly and retrieval quality restored.
```

---

## What you learned

- When RAG answers get bad, **look at the retrieved chunks first** - it tells you instantly whether the problem is retrieval (bad chunks) or generation (bad prompt).
- Chunks that are too small lose context and split facts; chunks that are too big blur meaning and waste prompt budget. Aim for coherent passages on natural boundaries, with a little overlap.
- Chunking is the highest-leverage ingestion decision. It is also the cheapest thing to get wrong and the easiest to fix - just re-chunk and re-ingest.
- In production, keep an eval golden set (USE exercise 1) so a chunking regression shows up as a drop in retrieval hit rate before users notice.
