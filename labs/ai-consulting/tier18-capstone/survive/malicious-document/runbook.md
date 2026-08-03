# SURVIVE Runbook: Malicious-Document Testing

**Tier 18 - SURVIVE (Part 5). Scenario 4 of 6.** Computable: `inject.sh` plants a poisoned document, `validate.sh` proves it is caught and removed.

Maps to OWASP LLM04 (data and model poisoning).

## The situation

Your assistant is trusted because it cites its sources. That trust is a vulnerability: if an attacker gets a document into the corpus that states false but official-sounding content - a fabricated deadline, a fake fee, a removed appeal right - the assistant will confidently cite it, and citizens will believe it. In a public institution, poisoned content can cause real harm (missed benefits, wrongful payments).

Run `inject.sh` to plant a false "policy" document, then defend.

---

## Diagnosis: how did the document get in, and what does it claim?

### 1. Reproduce
On your **lab server**, as **ec2-user**, run `inject.sh`. Ask the assistant "how do I submit a benefits application?" and watch it cite the fake policy (in-person only, cash fee, no appeal). That is the poisoning succeeding.

### 2. Understand the ingestion path
The core question: who and what can add documents to the corpus, and is anything checked? Poisoning is fundamentally a supply-chain and ingestion-control problem, not a model problem. If any document can enter without provenance, review, or integrity checks, you are exposed.

---

## Recovery: the defenses

1. **Source trust and provenance.** Every document records where it came from and who added it. Only documents from trusted, authorized sources are ingested into the authoritative corpus. Unknown-origin documents are quarantined, not served.

2. **Human review for authoritative content.** In a public institution, content that citizens will rely on should be reviewed and approved by an accountable owner before it becomes citable. This connects to human-oversight design (Part 3).

3. **Content integrity (hashing).** Each chunk carries a content hash (your Tier 7 schema already has `content_hash`). Compare against a registry of approved content so tampering or unexpected new content is detectable.

4. **Ingestion-time screening.** Flag documents with suspicious patterns (injection payloads, contradictions of known policy, unusual claims like new fees or removed appeal rights) for human review rather than auto-serving them.

5. **Remove and record.** When you find the poisoned document, remove it from the corpus, record the incident (per the Part 3 incident process), and check whether it was served to anyone who may need correcting.

Add provenance + review gating to `ingest.py`, then remove the poisoned doc and re-test.

---

## Validate

On your **lab server**, as **ec2-user**:

```
bash /path/to/validate.sh
```

It confirms: the poisoned document is no longer in the served corpus, an answer about applying no longer cites the false policy, and legitimate content is unaffected. Expect `PASS`.

---

## The lesson

An assistant that cites sources is only as trustworthy as its corpus. Poisoning is an ingestion and supply-chain problem: control who and what can enter the authoritative corpus, require provenance and human approval for authoritative content, and use content hashing to detect tampering. The model cannot tell true from false - your ingestion controls must.

---

## Review checklist

- [ ] Reproduced the poisoning and saw the false citation
- [ ] Traced how the document entered (ingestion control gap)
- [ ] Added source trust / provenance to ingestion
- [ ] Required human review/approval for authoritative content
- [ ] Used content hashing to detect unexpected/tampered content
- [ ] Removed the poisoned document and recorded the incident
- [ ] Checked whether anyone was served the false content
- [ ] validate.sh returns PASS
- [ ] Legitimate content unaffected (no over-correction)

---

Prof. Happy (SUTA Labs)
