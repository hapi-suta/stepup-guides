# Concepts 13.3: Google Cloud AI

**Tier 13 - Cloud AI platforms.** A teaching reference for the third major cloud. AWS is your primary; Azure and Google Cloud (GCP) are the ones you understand well enough to recommend and compare. GCP shows up with clients who are data-and-analytics heavy (big BigQuery estates), who want Google's Gemini models, or who already run on Google.

**Who this is for:** you know the AWS stack (13.1) and the Azure map (13.2). We teach GCP the same way - by mapping to what you know, then noting where Google is genuinely distinctive.

---

## 1. Why a client would choose GCP

- **Data-and-analytics gravity.** If the client's data already lives in **BigQuery** (Google's serverless data warehouse), doing AI right next to that data - even running models from SQL - is compelling. This is Google's strongest pull.
- **Gemini models.** A client who specifically wants Google's Gemini family in their own cloud boundary lands on GCP, the way an OpenAI-wanting client lands on Azure.
- **Existing Google footprint.** Shops already on Google Workspace or GCP infrastructure default here for the same ecosystem reasons Microsoft shops default to Azure.

Same consultant principle as always: the best cloud is usually the one the client already runs. Reduce lock-in with your own abstraction rather than by relocating the client.

---

## 2. The AWS-to-GCP map

| Need | AWS | GCP |
|---|---|---|
| Hosted foundation models + ML platform | Bedrock + SageMaker | **Vertex AI** |
| Model catalog (choose a model) | Bedrock model access | **Model Garden** |
| Managed agents | Bedrock Agents | **Vertex AI Agent Builder** |
| AI directly on warehouse data | (Redshift ML, roughly) | **BigQuery ML** |
| Identity and access | IAM | **Cloud IAM** |
| Secrets | Secrets Manager | **Secret Manager** |
| Keys | KMS | **Cloud KMS** |
| Object storage | S3 | **Cloud Storage** |
| Serverless functions | Lambda | **Cloud Run functions** (formerly Cloud Functions) |
| Containers | ECS/EKS | **Cloud Run** / **GKE** |
| Private network | VPC | **VPC** (also called VPC) |
| Monitoring and alarms | CloudWatch | **Cloud Monitoring** (Cloud Operations) |

Note that GCP folds more into one product: **Vertex AI** covers what AWS splits between Bedrock and SageMaker. That can feel simpler, or it can feel like one big surface to learn - depends on the client.

---

## 3. Vertex AI

**Vertex AI** is Google's unified AI platform. Through one service you get:

- Access to **Gemini** and other foundation models (hosted, call-an-API, pay per token) - the Bedrock-style path.
- Custom training, tuning, and model hosting - the SageMaker-style path.
- Evaluation, pipelines, and MLOps tooling.

So where AWS makes you choose a front door (Bedrock vs SageMaker), Vertex is the single front door for both call-an-API and build-your-own. For an LLM feature you use Vertex's foundation-model APIs; you do not need the training half unless the client trains models. (Naming note: Google has begun rebranding this platform under its "Gemini Enterprise" agent branding; "Vertex AI" still resolves and remains the name most docs use, but expect the umbrella name to keep shifting - describe the capability, verify the current name at https://cloud.google.com/vertex-ai.)

---

## 4. Model Garden and Agent Builder

**Model Garden** is Vertex's catalog - a browsable set of first-party (Gemini), open, and partner models you can select and deploy. It is the "choose your model" surface, analogous to enabling model access in Bedrock or browsing Azure's model catalog. It reinforces the anti-lock-in point: even within one cloud, keep your calls behind an abstraction so swapping the model in Model Garden is a small change.

**Agent Builder** is Google's managed agent and search offering - build a grounded agent or an enterprise search experience over your own data, the managed analog of Tier 8 and of Bedrock Agents. Naming caution: this area is rebranding fast. "Vertex AI Agent Builder" has been folded into "AI Applications," and Google has added an open-source **Agent Development Kit (ADK)** for building agents plus **Agent Engine** as a managed runtime. The concept (managed grounded agents over your data) is stable; confirm the current product name at https://cloud.google.com/products/agent-builder before writing it into a deliverable.

---

## 5. BigQuery ML - the distinctive one

**BigQuery ML** lets analysts build and run machine-learning models, and even call foundation models (via Vertex AI), using plain SQL right inside the BigQuery data warehouse - no data movement, no separate ML pipeline (see: https://cloud.google.com/bigquery/docs/bqml-introduction). For a client whose data and analysts already live in BigQuery, this is a genuine differentiator: they can get value from AI without a data-engineering project to move data somewhere else first.

Consultant takeaway: if a prospect's data center of gravity is BigQuery, GCP deserves serious consideration on that basis alone. Data gravity - the cost and risk of moving large data - is a real architectural force, and moving compute to the data often beats moving data to the compute.

---

## 6. Identity, secrets, keys, network - the familiar discipline

- **Cloud IAM** - Google's IAM. Same model: roles and permissions, least privilege, no broad wildcards. Prefer **service accounts** (the assumable-identity analog) for applications over long-lived keys.
- **Secret Manager** and **Cloud KMS** - the direct analogs of AWS Secrets Manager and KMS. Store secrets and keys here, read at runtime via the service account, design for key rotation.
- **VPC** and private access (Private Service Connect / VPC Service Controls) - keep model endpoints private for regulated data, exactly as on AWS and Azure.
- **Cloud Monitoring** - metrics, logs, dashboards, and **alerting policies** (the alarm analog) on cost and volume anomalies.

Every security lesson from AWS transfers. Only the names change.

---

## 7. Safety and grounding

Vertex provides configurable **safety filters** and **grounding** options (including grounding against your own data and against Google Search where appropriate). The concept matches Bedrock Guardrails and Azure Content Safety: screen inputs and outputs, and ground answers to reduce hallucination. Place it in front of every model call.

---

## 8. The three-cloud comparison a consultant carries

When a client asks "which cloud", you reason across a small set of axes. This is the shape of the comparison you produce in BUILD Project 13:

| Axis | AWS | Azure | GCP |
|---|---|---|---|
| Default fit | Broadest enterprise footprint | Microsoft / Entra shops, want GPT | Data/BigQuery-heavy, want Gemini |
| Flagship AI | Bedrock (+ SageMaker) | Azure OpenAI / AI Foundry | Vertex AI (+ Model Garden) |
| Distinctive strength | Breadth and maturity | OpenAI models + M365 integration | AI on warehouse data (BigQuery ML) |
| Data on warehouse | Redshift ML (weaker) | Fabric/Synapse | BigQuery ML (strongest) |
| Identity advantage | Deep IAM | Entra ID SSO if already Microsoft | Workspace integration |

The honest answer is almost never "cloud X is best". It is "given your existing footprint, your data gravity, the models you want, and your compliance needs, here is the fit - and here is how we keep you portable regardless".

---

## 9. The consultant's summary

- Vertex AI is GCP's single front door for both hosted models and custom ML.
- GCP's standout is AI on data already in BigQuery - watch for data gravity.
- The identity/secrets/keys/network/monitoring discipline is identical to AWS and Azure; only names change (service accounts, Secret Manager, Cloud KMS, Cloud Monitoring).
- Recommend by the client's real footprint, data gravity, model preference, and compliance - not by fashion.
- Keep model calls behind your own abstraction on every cloud, so a client is never locked to Vertex, Bedrock, or Azure OpenAI. Portability is designed in.

---

## References

- Vertex AI - introduction (unified platform) - https://cloud.google.com/vertex-ai/docs/start/introduction-unified-platform
- Vertex AI Model Garden - https://cloud.google.com/model-garden
- Vertex AI Agent Builder / AI Applications - https://cloud.google.com/products/agent-builder
- BigQuery ML - introduction (ML and foundation models via SQL) - https://cloud.google.com/bigquery/docs/bqml-introduction
- Cloud Functions is now Cloud Run functions - https://cloud.google.com/blog/products/serverless/google-cloud-functions-is-now-cloud-run-functions
- Vertex AI - grounding overview (own data + Google Search) - https://cloud.google.com/vertex-ai/generative-ai/docs/grounding/overview

Prof. Happy (SUTA Labs)
