# USE: Worked Examples and the Pre-Publish Check

**Tier 17 - USE phase.** This file shows two artifact types worked out fully - a technical article and a case study - so you see the level of grounding expected, plus the pre-publish check you run on every piece before it goes live.

**Validated on:** editorial review, 2026-07-25.

---

## Worked example 1: Technical article (excerpt)

Theme: multilingual RAG for English/French/Pidgin. Note how every section is specific and how the limits section is honest.

---

### Why English-Only Evaluation Hides Your Assistant's Worst Failures

**The problem.** A public agency deployed a bilingual assistant and measured 92 percent answer accuracy. Leadership was pleased. When we broke the evaluation out by language, English scored 96 percent and the local-language queries scored 71 percent. The blended number had hidden a serious failure for the citizens who most needed the service.

**The claim.** Any multilingual assistant evaluated only on a blended metric is hiding uneven quality across languages, and the gap almost always falls on the lower-resource language.

**The evidence.** Across three deployments we measured, the lower-resource language trailed the dominant language by 15 to 25 points on retrieval hit-rate. The cause was consistent: embeddings trained mostly on high-resource text retrieve worse for the low-resource language, so the model answers from weaker context. (This is our own measured work across three engagements; the pattern matches the well-documented resource imbalance in multilingual embedding models.)

**The method.** Evaluate per language, never blended. Build a golden set with equal coverage per language. Report retrieval hit-rate and answer accuracy separately per language. Treat the lowest-language score as the real quality of the system, because that is the experience of the citizen it fails.

**Where this does not apply.** If your user base is genuinely single-language, a blended metric is fine. And per-language evaluation needs enough golden examples per language to be statistically meaningful; below roughly 50 items per language, treat the numbers as directional, not precise.

**Takeaway.** Report per language, and judge the assistant by its weakest language, not its average.

---

Notice: a real observed number, an honest "this is our own measured work" attribution, a reusable method, and explicit limits. That is a defensible article.

---

## Worked example 2: Case study (excerpt)

Theme: responsible AI adoption in an African public institution. Fully anonymized.

---

### Case Study: Standing Up Governed Document Search at a [INDUSTRY] Public Agency

**Permission obtained:** yes. **Identifying detail removed:** confirmed (sector generalized, figures rounded, no names).

**Context.** A public agency in a lower-resource setting wanted staff to find policy quickly across thousands of scattered documents. They had no AI governance, unclassified records, intermittent connectivity, and a bilingual staff. Leadership wanted "an AI" and expected magic.

**The approach.** We refused to start with a flashy citizen chatbot. We ran a readiness assessment (Tier 16 method), which scored data readiness low - records were unclassified, so access control was impossible. Phase 1 became: classify records, then deploy an internal, staff-only, cited document-search assistant. We adapted the governance toolkit for the sector, made access control map to records classification, and built appeal-grade logging from the start. We evaluated per language.

**What happened.** Staff search time for a policy dropped from about 20 minutes to under 3 on the queries we measured. Adoption was high because the tool cited its sources, so staff trusted it. What did not work at first: the low-resource-language retrieval lagged badly until we rebalanced the golden set and adjusted chunking. We also underestimated connectivity, and had to add offline-tolerant behavior.

**Lessons.** Start administrative and internal, not citizen-facing. Classify data before you can govern access. Evaluate per language or you will ship a tool that fails your most vulnerable users. Design for the appeal and the audit before go-live.

**Reusable method.** Readiness assessment -> data classification -> internal cited assistant -> per-language evaluation -> governance from day one -> then, and only then, consider citizen-facing use.

---

Notice: honest about what did not work, rounded figures, generalized sector, permission stated, and a reusable method. That is a case study that builds credibility rather than exposing a client.

---

## The pre-publish check (run on EVERY piece)

Before anything goes live, walk this list. If any answer is "no", do not publish yet.

- [ ] Is my central claim specific and falsifiable (not a vague opinion)?
- [ ] Can I produce evidence for every factual claim if challenged?
- [ ] Is every citation real and verifiable? (No hallucinated sources. Check each one.)
- [ ] Have I stated the limits - where this does not apply?
- [ ] If this is client work, do I have permission and have I removed identifying detail?
- [ ] Have I distinguished my own measured work from others' findings?
- [ ] Would I be comfortable defending this in front of an expert who disagrees?
- [ ] Is it written for a stated audience in their language?
- [ ] Have I logged it in the publication tracker?

The single most important line is "every citation real and verifiable." A fabricated citation, caught once, can end your credibility. Verify each source by hand.

---

Prof. Happy (SUTA Labs)
