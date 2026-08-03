# USE: Produce a Data-Flow Diagram with Trust Boundaries

**Goal:** the plan wants a data-flow diagram with trust boundaries for one real system. You will diagram the knowledge assistant from Project 11 - every entry point, every hop the data takes, and every line where control passes between trusted and untrusted. This is the visual core of the threat model (Module 11.3): once you can see the trust boundaries, you know exactly where controls must live.

**Where you are:** the lab server (CentOS Stream 9), as **ec2-user**, with Project 11 in `~/project11`. No paid key needed - this exercise is about reading the code and drawing the flows.

**What you will practice:** tracing data, identifying trust boundaries, and mapping each boundary to a control - the skills a client pays a consultant to bring.

---

## Step 1: List the entry points from the code

On your **lab server**, as **ec2-user**:

```bash
cd ~/project11
```

Find every route the app exposes:

```bash
grep -n "@app" app.py
```

Expected output (yours will differ):

```
52:@app.get("/health")
57:@app.post("/ask")
73:@app.post("/lookup")
```

Those are your **entry points**: `/health` (trivial), `/ask` (the RAG path), and `/lookup` (the tool). Each is attack surface.

---

## Step 2: Trace the /ask data flow in the code

Read the `/ask` handler and follow where the data goes:

```bash
sed -n '57,80p' app.py
```

Expected output (yours will differ, truncated):

```
@app.post("/ask")
def ask(body: Ask):
    docs = store.retrieve(body.question)
    context = "\n\n".join(f"[doc:{d['source']}] {d['text']}" for d in docs)
    user_turn = f"Knowledge base:\n{context}\n\nQuestion: {body.question}"
    answer = llm.complete(SYSTEM_PROMPT, user_turn)
    return {"answer": answer, "docs_used": [d["source"] for d in docs]}
```

Trace it in words: **user question** enters -> `store.retrieve` pulls **documents** -> question + documents are merged into one **prompt** -> the prompt is sent to the **model provider** -> the **answer** returns to the user. Two untrusted inputs (the question and the retrieved documents) reach the model in the same turn.

---

## Step 3: Trace the document lifecycle

The documents were not born in the store - they were ingested. Look at the store:

```bash
cat knowledge.json
```

Each record has a `source` and a `trusted` flag. The lifecycle is: **document ingested** (from an upload, a drive, a scrape) -> **stored** -> later **retrieved** into an `/ask` prompt. That ingestion step is a separate entry point and a separate trust boundary - it is how a poisoned document gets in (the vector-store-poisoning SURVIVE).

---

## Step 4: Draw the diagram

Create the diagram as text (a client-ready version can be redrawn in any tool; the thinking is what matters):

```bash
vi data-flow.md
```

Press `i` and enter a diagram like this, then adjust to what you found:

```
                TRUST BOUNDARY (untrusted -> trusted)
   [ Employee ] --question--> | --> [ /ask endpoint ]
                              |
   [ Doc uploader ] --file--> | --> [ ingestion -> vector store ]
                              |            |
                              |         retrieve
                              |            v
                        [ build prompt: SYSTEM + docs + question ]
                              |
                TRUST BOUNDARY (your data leaves your control)
                              | --> [ Model provider (Claude / mock) ]
                              |            |
                              |          answer
                TRUST BOUNDARY (untrusted model output)
                              | --> [ /lookup tool ]  (acts on customer data)
                              | --> [ answer rendered to user ]

   Assets crossing here: knowledge base, customer PII (SSN),
   system-prompt secret, API spend.
```

Press `Esc`, type `:wq`, press Enter.

The three trust boundaries to mark clearly:
1. **Untrusted input -> your app** (user question, uploaded document).
2. **Your app -> model provider** (your data leaves your boundary).
3. **Model output -> action/UI** (untrusted completion drives a tool or a page).

---

## Step 5: Map each boundary to a control

Under the diagram, add the control that belongs at each boundary:

```bash
vi data-flow.md
```

Press `i` and append:

```
CONTROLS PER BOUNDARY
1. Untrusted input -> app:
   - validate/limit input; refuse extraction & injection phrasings
   - quarantine untrusted documents; ingest only from allowlisted sources
2. App -> model provider:
   - do not send secrets/PII you would not want the provider to hold
   - rate limit + budget cap (cost boundary is also a trust boundary)
3. Model output -> action/UI:
   - treat completion as untrusted: filter secrets, encode for the UI
   - authorize every tool call; require approval for dangerous actions
```

Press `Esc`, type `:wq`, press Enter.

Every control you will build in the SURVIVE scenarios now has a home on this diagram - that is not a coincidence. Controls live on trust boundaries.

---

## Step 6: Sanity-check against the running system

Confirm the boundaries you drew match reality. The model boundary: with no key, data goes to the local mock; with a key, it leaves to Claude. Check which:

```bash
echo "${ANTHROPIC_API_KEY:-<none - using local mock>}"
```

Expected output (if you have not set a key):

```
<none - using local mock>
```

That tells you exactly what crosses boundary 2 right now: nothing leaves your box. Set a key and it would - which is itself a finding worth stating in the assessment.

---

## What you practiced

- Tracing real data flows from the code, not from memory.
- Identifying the three trust boundaries that matter for any RAG assistant: input, provider, and output/action.
- Mapping each boundary to the control that belongs there - the bridge from diagram to defense.
- Producing a client-ready artifact that anchors the whole threat model.

Prof. Happy (SUTA Labs)
