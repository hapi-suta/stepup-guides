# USE: Data-Residency Comparison for an In-Region Client

**Tier 13 - USE phase.** Many clients - public sector, banks, healthcare, anyone under a data-protection law - have a hard rule: the data may not leave a specific region. That single constraint can decide the whole cloud choice, because not every cloud offers its AI service (and its logs and stored data) in every region. In this exercise you build a small tool that scores each cloud for a required region and produces the deliverable: a data-residency comparison the client can act on.

**Validated on:** CentOS Stream 9, Python 3.12. No cloud account required - this is grounded analysis, not a live cloud call.

**Prerequisite:** you read Concepts 13.1-13.3 and finished BUILD Project 13.

**Goal:** a reusable residency-check script and a written residency comparison and recommendation for a concrete client.

---

## The scenario

Your client, [CLIENT], is a national public-sector body. Their regulator requires that citizen data - and every copy of it, including logs and the AI service that processes it - stays inside the country's approved cloud region. They ask you a direct question: "Which clouds can we legally use for this AI assistant, and which ones can we not?" You must answer with evidence, not a shrug, and hand them something they can re-run when regions change.

The trap for a beginner: it is not enough that the cloud has *a* region in the country. The AI service itself (Bedrock, Azure OpenAI, Vertex) must be available *in that region*, and the logs and stored data must be pinnable there too. A cloud can have a data center in-region and still not offer its AI models there.

---

## Step 1: Set up the exercise folder

On your **lab server** (CentOS Stream 9), as **ec2-user**:

```bash
mkdir -p ~/use-residency
```

Move into it:

```bash
cd ~/use-residency
```

---

## Step 2: Write the residency-check tool

This tool scores each cloud on three things for a required region: is the AI service available there, can logs be pinned there, can stored data be pinned there. All three must pass or the cloud fails the residency test.

Still on your **lab server**, as **ec2-user**, in `~/use-residency`, open a new file:

```bash
vi residency_check.py
```

Press `i`, enter the following. Read the comments.

```python
#!/usr/bin/env python3
"""Data-residency comparison (Tier 13 USE).

A client with a hard "data must stay in-region" rule needs to know, per cloud,
whether the AI service, its logs, and its stored data can all be pinned to the
required region. This script scores each cloud and flags any component that
cannot be guaranteed in-region. No cloud account needed - analysis grounded in
each provider's regional model.
"""
import sys

# Simplified regional model. In a real engagement you confirm each cell against
# the provider's CURRENT region list and your contract, as of a dated snapshot.
CLOUDS = {
    "aws": {
        "service": "Bedrock",
        "regions_with_ai": {"us-east-1", "us-west-2", "eu-central-1", "eu-west-1",
                            "ca-central-1", "ap-southeast-2"},
        "logs_pinnable": True,
        "data_pinnable": True,
        "notes": "Enable only the in-region model; disable cross-region inference.",
    },
    "azure": {
        "service": "Azure OpenAI",
        "regions_with_ai": {"eastus", "westeurope", "canadacentral",
                            "australiaeast", "swedencentral"},
        "logs_pinnable": True,
        "data_pinnable": True,
        "notes": "Choose a regional deployment; avoid global tiers that can route out.",
    },
    "gcp": {
        "service": "Vertex AI",
        "regions_with_ai": {"us-central1", "europe-west1", "europe-west4",
                            "asia-southeast1", "northamerica-northeast1"},
        "logs_pinnable": True,
        "data_pinnable": True,
        "notes": "Use a regional endpoint; set data residency on the project.",
    },
}


def assess(required_region: str) -> list:
    """Return per-cloud residency verdict for a required region token."""
    out = []
    for cloud, cfg in CLOUDS.items():
        in_region = required_region in cfg["regions_with_ai"]
        verdict = "PASS" if (in_region and cfg["logs_pinnable"]
                             and cfg["data_pinnable"]) else "FAIL"
        out.append({
            "cloud": cloud, "service": cfg["service"], "ai_in_region": in_region,
            "logs_pinnable": cfg["logs_pinnable"], "data_pinnable": cfg["data_pinnable"],
            "verdict": verdict,
            "note": cfg["notes"] if in_region else
                    f"{cfg['service']} not available in {required_region}",
        })
    return out


def main() -> None:
    region = sys.argv[1] if len(sys.argv) > 1 else "eu-central-1"
    print(f"# Data-Residency Comparison - required region token: {region}\n")
    results = assess(region)
    print("| Cloud | Service | AI in region | Logs pinnable | Data pinnable | Verdict |")
    print("|---|---|---|---|---|---|")
    for r in results:
        print(f"| {r['cloud']} | {r['service']} | {r['ai_in_region']} "
              f"| {r['logs_pinnable']} | {r['data_pinnable']} | {r['verdict']} |")
    print("\nNotes:")
    for r in results:
        print(f"- {r['cloud']}: {r['note']}")


if __name__ == "__main__":
    main()
```

Press `Esc`, type `:wq`, press Enter.

Important note on region names: each cloud names its regions differently (`eu-central-1` on AWS, `westeurope` on Azure, `europe-west1` on GCP). A required geography maps to a different token per cloud, so in a real engagement you run the check with each cloud's own token. For this exercise we pass one token and see how it scores.

Run it for a European client whose approved region is AWS Frankfurt:

```bash
python3 residency_check.py eu-central-1
```

Expected output (yours will differ):

```
# Data-Residency Comparison - required region token: eu-central-1

| Cloud | Service | AI in region | Logs pinnable | Data pinnable | Verdict |
|---|---|---|---|---|---|
| aws | Bedrock | True | True | True | PASS |
| azure | Azure OpenAI | False | True | True | FAIL |
| gcp | Vertex AI | False | True | True | FAIL |

Notes:
- aws: Enable only the in-region model; disable cross-region inference.
- azure: Azure OpenAI not available in eu-central-1
- gcp: Vertex AI not available in eu-central-1
```

Read it carefully: AWS passes for the `eu-central-1` token; Azure and GCP fail *for that exact token* because they name the same geography differently. This is the trap - you must test each cloud with its own region name. The lesson for the client is that the residency requirement narrows the field fast.

---

## Step 3: Test the hard case - a region no cloud serves

Some geographies have no in-region AI service on any major cloud. This is common for African public-sector clients, which matters directly to your consulting focus. Try one:

```bash
python3 residency_check.py af-south-1
```

Expected output (yours will differ):

```
# Data-Residency Comparison - required region token: af-south-1

| Cloud | Service | AI in region | Logs pinnable | Data pinnable | Verdict |
|---|---|---|---|---|---|
| aws | Bedrock | False | True | True | FAIL |
| azure | Azure OpenAI | False | True | True | FAIL |
| gcp | Vertex AI | False | True | True | FAIL |

Notes:
- aws: Bedrock not available in af-south-1
- azure: Azure OpenAI not available in af-south-1
- gcp: Vertex AI not available in af-south-1
```

Every cloud fails. This is a real and important consulting finding: when no managed AI service exists in the required region, the honest recommendation is not "pick a cloud anyway" - it is a different architecture (a self-hosted open-weight model on in-region infrastructure, or an approved exception, or waiting for regional availability). Recognizing when the residency rule blocks every managed option is exactly the judgment a client pays you for.

---

## Step 4: Produce the deliverable

Capture the comparison for the client's approved region into a report:

```bash
python3 residency_check.py eu-central-1 > residency-comparison.md
```

`>` redirects the output into a file. Then add your written recommendation to the same file:

```bash
vi residency-comparison.md
```

Press `i`, move to the end (press `Esc` then `G` to jump to the last line, then `o` to open a new line below), and add (adapt to [CLIENT]):

```markdown

## Recommendation for [CLIENT]

- Approved region: [name it].
- Verified as of [DATE] against each provider's current region list.
- AWS Bedrock is available in the approved region and can pin the model, logs
  (CloudWatch), and stored data (S3 + KMS) in-region. Recommended primary.
- If the approved region has NO in-region managed AI service on any cloud, the
  recommendation changes to a self-hosted open-weight model on in-region
  infrastructure, or a documented, time-limited exception approved by the
  regulator - never a silent cross-region routing of citizen data.
- Re-run residency_check.py whenever regions change or the requirement changes.
```

Press `Esc`, type `:wq`, press Enter. You now have a residency comparison table plus a written, defensible recommendation - the deliverable.

---

## What you produced

- A reusable residency-check tool that scores each cloud on AI availability, log pinning, and data pinning for a required region.
- The insight that region names differ per cloud, so each must be tested with its own token.
- The harder insight that some regions have no managed AI service anywhere, which changes the recommendation entirely.
- A residency comparison report with a dated, defensible recommendation for the client.

Remember to write the date of your snapshot into the deliverable. Regional availability changes constantly, and a residency claim without a date is worthless to an auditor.

---

Prof. Happy (SUTA Labs)
