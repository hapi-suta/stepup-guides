# AI Vendor Assessment Questionnaire

**Vendor:** [VENDOR NAME] - **Product/model:** [PRODUCT]
**Assessed by:** [NAME] - **Date:** [DATE]
**For use case:** [USE CASE] - **Client:** [ORGANIZATION]

**Aligns to:** Concepts 12.6, NIST AI RMF (Govern - third parties), ISO/IEC 42001
(operational controls - suppliers).

> Send this to the vendor, or fill it from their documentation. Score each area,
> flag dealbreakers, then write the recommendation at the end. A dealbreaker fails
> the vendor regardless of total score.

---

## Scoring key
Score each area 1 (poor / high risk) to 5 (excellent / low risk), or N/A.
Weight (1-3) reflects how much this area matters for THIS client.

| # | Area | Question | Vendor answer | Score (1-5) | Weight (1-3) | Dealbreaker? |
|---|------|----------|---------------|-------------|--------------|--------------|
| 1 | Training-data statements | What was the model trained on? Any provenance/copyright concerns? | | | | |
| 2 | Customer-data usage | Do you use our prompts/data to train or improve models? Is there a no-training guarantee? | | | | |
| 3 | Retention | How long do you keep our prompts, outputs, and logs? Can we require deletion? | | | | |
| 4 | Data residency | Where is our data processed and stored? Can we pin a region? | | | | |
| 5 | Encryption | Encrypted in transit and at rest? Who holds the keys? BYOK? | | | | |
| 6 | Security certifications | SOC 2 Type II? ISO 27001? ISO/IEC 42001? Evidence? | | | | |
| 7 | Availability | Uptime SLA? Incident history? | | | | |
| 8 | Subprocessors | Who else touches our data (cloud, downstream models, support)? | | | | |
| 9 | Intellectual property | Who owns the outputs? Can we use them commercially? | | | | |
| 10 | Indemnification | Do you indemnify us against IP claims / breaches? Caps? | | | | |
| 11 | Model updates | How are models changed/deprecated? Notice period? Can we pin a version? | | | | |
| 12 | Exit procedures | How do we leave? Transition period? | | | | |
| 13 | Export capability | Can we export our data, embeddings, fine-tunes, config in a usable format? | | | | |
| 14 | Pricing risk | Pricing model? Exposure to price rises / usage spikes? | | | | |

## Scoring rollup

- Weighted score = sum of (score x weight) / sum of (weight x 5), as a percentage.
- Weighted score: [%]
- Dealbreakers found: [list, or "none"]

## Recommendation

> Fill this in. Be specific about required contract terms.

- **Verdict:** [proceed / proceed with conditions / reject]
- **Reasoning:** [TEXT]
- **Required contract terms before signing:** [e.g. no-training guarantee,
  in-region processing, 90-day model-deprecation notice, export in open format]
- **Ongoing management:** re-assess [FREQUENCY]; maintain a tested exit path.

Prof. Happy (SUTA Labs)
