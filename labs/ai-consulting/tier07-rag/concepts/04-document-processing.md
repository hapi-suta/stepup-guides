# Concepts: Document Processing

Retrieval quality is capped by ingestion quality. If you parse and chunk documents badly, no embedding model or LLM can save you - "garbage in, garbage out". This maps to the ingestion code in Project 7 and to the `bad-chunking` SURVIVE scenario.

---

## 1. The formats you will meet, and why each is hard

Real enterprise documents are messy. Each format has a trap:

- **PDF** - the hardest common case. A PDF stores *positioned glyphs*, not clean text. Extraction can jumble reading order (especially multi-column layouts), merge or split words, and lose tables. Some PDFs are just scanned images with no text at all (see OCR).
- **Word (.docx)** - actually a zip of XML; reasonably clean to extract, but watch for tracked changes, comments, and text boxes.
- **Spreadsheets (.xlsx/.csv)** - rows and columns, not prose. A naive text dump loses the meaning of "which column is this". You often want to serialise each row as "Column A is X, Column B is Y" so a chunk is self-describing.
- **HTML / wiki** - full of navigation, ads, and boilerplate wrapped around the actual content. You must strip the chrome and keep the article.
- **Plain text / Markdown** - the easy case, and what Project 7 uses for its sample corpus so you can focus on the RAG concepts, not on PDF wrangling.

The consultant's reality: **most of the effort in a real RAG project is ingestion**, not the fancy AI. Plan for it.

---

## 2. OCR and its limits

**OCR** (Optical Character Recognition) turns an image of text (a scanned contract, a photo of a page) into actual text. Necessary for scanned documents, but:

- It makes mistakes - `rn` read as `m`, `0` as `O`, garbled tables.
- It loses layout and reading order.
- Quality drops fast on poor scans, handwriting, and stamps.

So OCR'd text needs *more* cleaning, and you should treat its output as lower-confidence. For the demo you use clean text, but you must be able to tell a client "scanned documents need OCR, and OCR output is noisy - budget for cleanup and expect lower retrieval quality on those."

---

## 3. Cleaning

Before chunking, remove what pollutes retrieval:

- **Headers and footers** repeated on every page ("CONFIDENTIAL - Page 3 of 40").
- **Page numbers**, watermarks, line numbers.
- **Navigation and boilerplate** from HTML.
- **Excess whitespace** and control characters.

Why it matters: if every chunk ends with "Page 3 of 40", that repeated text dilutes the embedding and can even make unrelated chunks look similar (they share the boilerplate). Clean chunks embed more sharply.

---

## 4. Chunking - the highest-leverage decision

You retrieve *chunks*, so how you split documents largely determines retrieval quality.

- **Too big** - a chunk covers many topics; its embedding is a blurry average, and you waste prompt space (and money) pasting irrelevant text.
- **Too small** - a chunk lacks context ("It must be returned within 30 days." - *what* must?); retrieval matches fragments that do not stand alone.
- **Just right** - a few hundred words / a coherent passage, one main idea per chunk.

Techniques:

- **Fixed-size** - split every N characters/tokens. Simple, but cuts sentences in half.
- **Sentence/paragraph-aware** - split on natural boundaries so chunks are whole thoughts. Better.
- **Overlap** - let consecutive chunks share the last/first sentence or so, so a fact that straddles a boundary is not lost from both chunks. A common starting point is a few hundred tokens per chunk with roughly 10-20% overlap, but treat this as a tunable default, not a law - the right chunk size depends on your documents and your embedding model, and you should measure it with the retrieval metrics in [05-rag-evaluation.md](05-rag-evaluation.md) rather than trusting a fixed number.

Bad chunking is a real, common failure - the retriever returns technically-nearby but useless fragments. Your SURVIVE `bad-chunking` scenario injects a broken chunker (chunks too small / split mid-sentence); you diagnose it by looking at what gets retrieved, then re-chunk sensibly and confirm retrieval improves.

---

## 5. Tables, headers, and structure

- **Tables** lose all meaning when flattened to a text run. Options: keep them as small Markdown tables inside a chunk, or serialise row-by-row. Never let a table become a blob of numbers with no column labels.
- **Section headers** are gold - prepend the section title to each chunk ("Section: Refund Policy\n...") so the chunk carries its context and embeds more precisely.

---

## 6. Versions, deduplication, and confidentiality labels

Enterprise-specific concerns that separate a demo from a deployable system:

- **Versions** - documents change. You need to know which version a chunk came from, and re-ingest when a document is updated (and remove the old chunks, or the model will cite stale policy). Store a version/date in metadata.
- **Deduplication** - the same content often appears many times (an email thread quoting itself, a policy pasted into three wikis). Duplicate chunks crowd out other results and waste the prompt. Detect and drop near-duplicates (e.g. by hashing normalised chunk text).
- **Confidentiality labels** - many organisations tag documents "Public / Internal / Confidential / Restricted". You carry that label into chunk metadata and use it for access control (see [03-vector-databases.md](03-vector-databases.md) section 6). A document's label is not decoration - it is the input to your security filter.

The through-line: **metadata created at ingestion time is what powers filtering, access control, citation, versioning, and dedup at query time.** Skimp on metadata during ingestion and you cannot enforce security or cite sources later. Capture it up front.

Next: [05-rag-evaluation.md](05-rag-evaluation.md).

---

## References

Authoritative sources for the ingestion concepts in this document. Tooling and defaults change - verify current options before recommending them to a client.

- Chunking strategies and overlap (LangChain text splitters, a widely used reference implementation): https://python.langchain.com/docs/concepts/text_splitters/
- LlamaIndex on document loading, parsing, and node/chunk construction: https://docs.llamaindex.ai/en/stable/module_guides/loading/
- Embedding-model overlap/chunk-size guidance (sentence-transformers): https://sbert.net/
