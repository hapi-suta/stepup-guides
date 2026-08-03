# Concepts: Embeddings

Embeddings are the heart of retrieval. If you understand embeddings, the rest of RAG is plumbing. This maps directly to the `embed()` function you write in Project 7.

---

## 1. What an embedding is

An **embedding** is a list of numbers (a **vector**) that represents the *meaning* of a piece of text. Two texts that mean similar things get vectors that are close together; two texts that mean different things get vectors that are far apart.

```
"how do I reset my password"   -> [0.12, -0.03, 0.88, ... ]   (say, 384 numbers)
"I forgot my login credentials" -> [0.14, -0.01, 0.85, ... ]   (close to the above)
"what time does the office open" -> [-0.7, 0.4, 0.02, ... ]     (far from both)
```

The length of the list (here 384) is the **dimensionality**. Every vector from a given model has the same length. A common small CPU model, `sentence-transformers/all-MiniLM-L6-v2`, produces 384-dimensional vectors and runs fast on a CPU (see: huggingface.co/sentence-transformers/all-MiniLM-L6-v2); larger models produce 768, 1024, or more. For comparison, OpenAI's hosted `text-embedding-3-small` produces 1536-dimensional vectors and `text-embedding-3-large` produces 3072 (both let you request a shorter length; see: platform.openai.com/docs embeddings). Higher dimensionality can capture more nuance but costs more storage and compute per comparison.

You do not choose the numbers - an **embedding model** produces them. The model learned, from huge amounts of text, to place text with similar meaning near each other in this high-dimensional space.

---

## 2. Semantic similarity vs keyword matching

Old-school search matched keywords: to find "password reset" the document had to contain those exact words. That misses "I forgot my login credentials" - no shared keywords, same meaning.

Embeddings capture **semantic similarity** - similarity of *meaning*, not of *words*. This is why RAG retrieval finds the right chunk even when the user's wording is nothing like the document's wording. It is the whole reason embeddings beat keyword search for question answering.

(Keyword search still has its place - it nails exact terms, product codes, error numbers. Combining both is *hybrid search*, which you build in USE exercise 2.)

---

## 3. Cosine similarity - how "close" is measured

Given two vectors, how do you score how similar they are? The standard measure in RAG is **cosine similarity**: the cosine of the angle between the two vectors.

- Cosine similarity of **1.0** - identical direction (most similar).
- Cosine similarity of **0.0** - perpendicular (unrelated).
- Cosine similarity of **-1.0** - opposite direction (most dissimilar).

You do not compute it by hand - pgvector's `<=>` operator gives you cosine *distance*, which is `1 - cosine similarity`, so **smaller distance means more similar**. Because similarity runs from 1 down to -1, cosine *distance* runs from **0 (identical direction) to 1 (perpendicular) to 2 (opposite)** - so if you ever want the similarity back, compute `1 - (embedding <=> :query_vector)` (see: github.com/pgvector/pgvector). When you write `ORDER BY embedding <=> :query_vector LIMIT 5`, you are asking Postgres for the 5 chunks whose meaning is closest to the question. That single line is retrieval.

The pgvector distance operators you will see:

- `<=>` cosine distance (use this for text embeddings - it ignores vector length and compares direction only).
- `<->` Euclidean (L2) distance (straight-line distance).
- `<#>` negative inner product (returns the negative value, an indexing quirk).

For text-meaning search, cosine (`<=>`) is the default and the right choice, and it is what sentence-transformers uses by default for semantic search (see: sbert.net). Note: if your vectors are already length-normalized (many embedding models return unit vectors), cosine and inner product rank results identically - cosine just does the normalization for you.

---

## 4. Choosing an embedding model

Trade-offs a consultant weighs:

- **Size / speed** - small models (384-dim) run fast on a CPU; large models are more accurate but need a GPU or an API. For an offline demo box you use a small CPU model.
- **Domain** - a general model is fine for general text. For law, medicine, or finance, a **domain-specific** model trained on that jargon retrieves noticeably better.
- **Multilingual** - if your documents are in more than one language (Project 7 is bilingual English/French), you need a **multilingual** model (for example `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`, which covers 50+ languages, or the multilingual-e5 family), so that an English question can match a French chunk and vice versa. These models are trained to place the same meaning in different languages near each other in one shared space. A single-language model would fail across languages, and keyword/sparse search cannot bridge languages at all.
- **Local vs API** - a local model keeps your documents on your infrastructure (important for confidential data); an API model is often more accurate but sends your text to a third party.

To compare candidate models objectively, consultants lean on **MTEB** (the Massive Text Embedding Benchmark), the standard public leaderboard that scores embedding models across many task types and languages (see: huggingface.co/spaces/mteb/leaderboard). Use it as a starting shortlist, then always re-test the finalists on the client's own documents - a leaderboard rank is not a guarantee for your domain.

**The rule that trips everyone up: you must embed queries with the exact same model you embedded the chunks with.** The numbers only mean the same thing if they came from the same model. Mixing models is like measuring one thing in inches and another in centimetres and comparing the raw numbers. (One subtlety: some models - E5, BGE - are *asymmetric* and want a different text *prefix* for a query versus a stored passage, e.g. `query:` vs `passage:`. That is still the same model, just told which role the text plays; the same-model rule holds.)

---

## 5. The offline fallback: hashing embeddings

Real embedding models need to download weights and, ideally, some compute. To keep Project 7 runnable offline on a tiny box with no downloads, the BUILD includes a **deterministic hashing embedding** fallback:

- It turns text into a fixed-length vector using hashing (each word bumps certain positions of the vector).
- It is **deterministic** - the same text always produces the same vector - which is exactly what you need for correctness and for tests.
- It captures *word overlap*, not deep meaning, so its retrieval quality is lower than a real model - but it proves the whole pipeline works, runs instantly, and needs zero dependencies.

In the BUILD you will see both paths: use a small `sentence-transformers` model if it is installed, otherwise fall back to hashing embeddings. Everything downstream (storage, retrieval, citation, generation) is identical either way. This is a common real pattern: build against an interface, swap the implementation.

---

## 6. Embedding versions - the silent killer

An embedding model has a **version**. If someone upgrades the model (v1 -> v2), the new model produces *different numbers* for the same text. Your stored chunk vectors were made with v1. New questions get embedded with v2. Now v2 question vectors are being compared against v1 chunk vectors - **and the comparison is meaningless**. Retrieval quietly returns garbage, but no error is raised and the system keeps "working".

The fix: whenever the embedding model changes, you must **re-embed every chunk** (re-index) with the new model, and you should **record the model name/version alongside each vector** so you can detect a mismatch. This exact failure is your SURVIVE `embedding-version-change` scenario - detect it, then re-index.

Next: [03-vector-databases.md](03-vector-databases.md).

---

## References

Authoritative sources used to fact-check this document. Model names, dimensions, and defaults change - reconfirm before quoting specifics to a client.

- sentence-transformers (library, semantic-search defaults, cosine similarity): https://sbert.net/ and https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
- Multilingual sentence-transformers: https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2
- OpenAI embedding models and dimensions (text-embedding-3-small/large): https://platform.openai.com/docs/guides/embeddings
- MTEB embedding-model leaderboard: https://huggingface.co/spaces/mteb/leaderboard
- pgvector distance operators and cosine-distance range: https://github.com/pgvector/pgvector
