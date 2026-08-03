# Concepts 13.1: AWS AI Architecture

**Tier 13 - Cloud AI platforms.** This is a teaching reference, not a lab. Read it, keep the ideas in your head, and come back to it when a BUILD or USE step names a service you want to double-check. You do not need to memorize service limits or click paths. You need a clear mental model of how the pieces of AWS fit together so that when a client says "we are an AWS shop, put our AI here", you can design something secure, observable, and not accidentally locked in.

**Who this is for:** you are a DBA moving into AI consulting. You already reason about servers, networks, identity, secrets, and failure. AWS is a very large catalog of managed versions of things you already understand. We build the picture from the parts that matter for an AI deployment and ignore the rest.

**Why AWS is the primary cloud in this plan.** It is the market leader, it is what most enterprise clients already run, and its AI stack (Bedrock plus the surrounding platform) is broad and mature. You learn AWS deeply and the others by comparison. Do not build your consulting identity around a single cloud any more than around a single model - but you need one you know cold, and that is AWS.

---

## 1. The two ways to do AI on AWS

There are two front doors, and a consultant must not confuse them.

**Amazon Bedrock** is a managed service that gives you API access to foundation models without running any servers. The model catalog spans multiple providers: Anthropic Claude, Amazon's own models (the newer **Nova** family is Amazon's current flagship; the older **Titan** models are still supported but de-emphasized), Meta Llama, Mistral, AI21, Cohere, and others - the list grows, so verify the current catalog at https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html. You call an API, you pay per token, AWS runs the model. This is the fast path and the right default for most clients who want an LLM feature. It is the AWS equivalent of calling a hosted model API, but inside your AWS account, under AWS identity and billing, with the data-handling story staying in AWS.

**Amazon SageMaker** is the full machine-learning platform: you bring or build models, train them, tune them, and host your own endpoints on infrastructure you configure. This is the heavy path for teams that train custom models or self-host open-weight models. Most AI-consulting engagements that just need "an LLM feature" do NOT need SageMaker - reaching for it when Bedrock would do is a classic over-engineering mistake.

The one-sentence version for a client: *"Bedrock is call-an-API-and-pay-per-token, no servers; SageMaker is bring-your-own-model-and-run-it, for teams that train or self-host."*

---

## 2. Amazon Bedrock in detail

Bedrock is more than raw model calls. The pieces a consultant should know:

- **Model access.** Historically you had to explicitly enable each model in the Bedrock console before you could call it, and "AccessDeniedException" usually meant you had not. **This changed in October 2025**: in commercial regions Bedrock now grants access to serverless foundation models automatically, governed by ordinary IAM permissions rather than a separate enable step (see: https://aws.amazon.com/blogs/security/simplified-amazon-bedrock-model-access/). Two carve-outs remain: Anthropic models require a one-time usage form before first use, and some AWS Marketplace models auto-create a subscription on first invocation. So today an AccessDenied is much more likely to be an **IAM** problem than a "you forgot to enable it" problem - which is the opposite of the old advice. Always check current behavior, since AWS iterates on this.
- **The `InvokeModel` / `Converse` API.** `InvokeModel` is the low-level per-provider call. The **Converse API** (`Converse` / `ConverseStream`) is a unified message interface that works the same across model families - AWS recommends it, and using it makes switching models a one-parameter change, which is exactly the anti-lock-in design from Tier 6 (see: https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference.html).
- **Knowledge Bases.** A managed RAG offering: point it at documents in S3, it chunks, embeds, and stores them in a vector store (OpenSearch Serverless, Aurora PostgreSQL with pgvector, Neptune Analytics, Pinecone, MongoDB Atlas, and others), and answers grounded questions with citations. It is a managed version of what you built by hand in Tier 7 (see: https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base-setup.html).
- **Agents.** A managed agent runtime: define tools (as Lambda functions or APIs), give the agent instructions, and it plans and calls tools - the managed version of Tier 8. Naming caution: the original offering is now called **Bedrock Agents (Classic)** and AWS has announced it is closing to new customers, with **Amazon Bedrock AgentCore** as the forward, framework-agnostic agent product (Runtime + Gateway). If you scope agent work on Bedrock, confirm which product the client should build on at https://aws.amazon.com/bedrock/agentcore/ - do not assume "Bedrock Agents" means the old thing.
- **Guardrails.** A safety layer you place in front of a model: it filters denied topics, blocks harmful content, redacts or blocks PII, and can run contextual-grounding (hallucination) checks. You attach a guardrail to a call and it screens both the input and the output (see: https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html). You will put Guardrails in front of your assistant in USE.

The key consultant point: Bedrock lets a regulated client get RAG, agents, and safety filtering as managed services inside their own AWS boundary, instead of building each from scratch. The trade-off is you are now leaning on AWS-specific services - which is fine if you keep the model calls behind your own abstraction so you can leave.

---

## 3. Identity and access: IAM

**IAM (Identity and Access Management)** is how AWS decides who can do what. Everything in AWS is default-deny: an identity can do nothing until a policy grants it. The pieces:

- **Users** - long-lived identities for people (avoid for applications).
- **Roles** - identities that are *assumed* temporarily and hand out short-lived credentials. Applications and AWS services (Lambda, ECS, EC2) should use roles, never long-lived keys. This is the single most important security habit on AWS.
- **Policies** - JSON documents that say "this identity may (or may not) perform these actions on these resources". Follow **least privilege**: grant only the specific actions and resources needed, nothing more (`bedrock:InvokeModel` on the one model, not `bedrock:*` on everything).

Why you care as a consultant: the most common cloud AI breach is not a clever attack, it is a misconfigured IAM policy or an S3 bucket left open. Getting IAM right - roles not keys, least privilege, no wildcards on sensitive actions - is most of your security posture. You will diagnose exactly this failure in the IAM SURVIVE scenario.

---

## 4. The network: VPC

A **VPC (Virtual Private Cloud)** is your own private network inside AWS. You control its subnets, routing, and what can reach the internet. For an AI deployment:

- Put your application (ECS/EKS tasks, Lambda) in **private subnets** with no direct internet exposure.
- Use a **VPC endpoint** (PrivateLink) for Bedrock so your model calls never traverse the public internet - they stay on the AWS backbone inside your VPC. Regulated clients often require this.
- Use **security groups** (stateful, instance-level firewalls) to allow only the traffic each component needs.

The mental model: the VPC is the building, subnets are floors, security groups are the locks on each door. A model call over a VPC endpoint is like an internal phone line instead of shouting out the window.

---

## 5. Storage: S3

**S3 (Simple Storage Service)** is object storage - the default place documents, model inputs, logs, and backups live on AWS. For AI it is where your RAG source documents and your Bedrock Knowledge Base data sit. What a consultant must know:

- **Buckets are private by default, and S3 Block Public Access is enabled by default on new buckets** (since April 2023; see: https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html) - but a misconfigured bucket policy or a deliberately disabled public-access setting is still the classic data-leak. Keep Block Public Access on at the account level unless you have a hard reason not to.
- **Encrypt at rest** with KMS (next section). PII documents demand it.
- **Versioning and lifecycle** protect against accidental deletion and control cost.

---

## 6. Encryption and secrets: KMS and Secrets Manager

**KMS (Key Management Service)** manages encryption keys. You use a KMS key to encrypt S3 objects, database volumes, and other data at rest. Keys can be rotated. The consultant point: encryption at rest with a customer-managed KMS key is table stakes for regulated data, and key **rotation** is something you must design for - if the app assumes a key never changes, rotation breaks it (you will see exactly this in the KMS SURVIVE scenario).

**Secrets Manager** stores secrets (API keys, database passwords, third-party credentials) encrypted, and hands them to your app at runtime through IAM - so nothing is hardcoded and secrets can be rotated centrally. This is the AWS-native answer to the "never hardcode a secret" rule from Tier 1. Your application reads the secret at startup via its IAM role; it never ships in the code or the container image.

---

## 7. Compute: Lambda, ECS, EKS

Where your application code runs:

- **Lambda** - functions that run on demand with no servers to manage. Great for event-driven glue, ingestion triggers, and light API backends. Scales to zero, you pay per invocation.
- **ECS (Elastic Container Service)** - runs your Docker containers, either on managed instances or on **Fargate** (serverless containers, no instances to patch). The usual home for a containerized RAG API.
- **EKS (Elastic Kubernetes Service)** - managed Kubernetes, for teams already standardized on Kubernetes or needing its portability. More power, more operational weight.

Consultant guidance: match the compute to the client's existing skills. Do not put a client on EKS because it is fashionable if they have never run Kubernetes - the operational burden will sink the project. Fargate/ECS or Lambda is usually the lower-risk recommendation.

---

## 8. Orchestration and integration: Step Functions and API Gateway

- **Step Functions** - a managed workflow engine that coordinates multiple steps (Lambda calls, waits, branches, retries) as a visual state machine. Use it for multi-step ingestion or agent-style pipelines where you want built-in retries and an audit trail of each step.
- **API Gateway** - a managed front door for your APIs: it handles authentication, throttling (rate limits), request validation, and routing to your backend. Putting an API Gateway in front of your assistant gives you the throttling and auth layer from Tier 9 as a managed service.

---

## 9. Observability: CloudWatch

**CloudWatch** is the AWS monitoring service: metrics, logs, dashboards, and **alarms**. For an AI deployment you watch Bedrock invocation counts, token usage, latency, and error rates, and you set **alarms** that fire on anomalies - for example, cost or invocation volume spiking (the runaway-usage problem from Tier 6). An alarm can trigger an action (notify a human, throttle, or cut off). You will wire a cost-anomaly alarm concept in the cost SURVIVE scenario. Without alarms you find out about a problem from the monthly bill, which is too late.

---

## 10. A reference AWS AI architecture

Putting it together, a secure Bedrock-based RAG assistant on AWS looks like:

1. Documents land in an **S3** bucket (private, KMS-encrypted, public access blocked).
2. A **Lambda** or **Step Functions** pipeline ingests them into a **Bedrock Knowledge Base** (or your own pgvector store).
3. The application runs as a container on **ECS/Fargate** in a **private subnet** of a **VPC**.
4. It reaches Bedrock over a **VPC endpoint**, assuming an **IAM role** with least-privilege access to only the one model and the one bucket.
5. Secrets come from **Secrets Manager**; data is encrypted with **KMS**.
6. **API Gateway** fronts the app for auth and throttling.
7. A **Bedrock Guardrail** screens every model call.
8. **CloudWatch** collects metrics and logs, with **alarms** on cost and errors.

Notice what makes this a consultant's architecture and not just a demo: identity is roles with least privilege, data is encrypted, model calls stay private, safety is enforced, and someone gets paged before the bill explodes. Notice also the one design choice that keeps the client free: the model calls go through the Converse API behind your own thin interface, so moving off Bedrock later is a contained change, not a rewrite.

---

## 11. The consultant's summary

- Bedrock for call-an-API LLM work; SageMaker only when the client trains or self-hosts.
- Roles, not long-lived keys. Least privilege, no wildcards on sensitive actions.
- Encrypt at rest (KMS), store secrets in Secrets Manager, keep model calls private (VPC endpoint).
- Put Guardrails in front, alarms on cost and errors, and everything behind your own model abstraction so the client is never trapped.

Get these right and "put our AI on AWS" becomes a secure, observable, portable system instead of an open bucket and a surprise bill.

---

## References

- Amazon Bedrock - supported foundation models - https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html
- Amazon Bedrock - simplified model access (auto-access, Oct 2025) - https://aws.amazon.com/blogs/security/simplified-amazon-bedrock-model-access/
- Amazon Bedrock - Converse API - https://docs.aws.amazon.com/bedrock/latest/userguide/conversation-inference.html
- Amazon Bedrock - Knowledge Bases - https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base-setup.html
- Amazon Bedrock AgentCore (current agent product) - https://aws.amazon.com/bedrock/agentcore/
- Amazon Bedrock - Guardrails - https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html
- Amazon Bedrock - VPC interface endpoints (PrivateLink) - https://docs.aws.amazon.com/bedrock/latest/userguide/vpc-interface-endpoints.html
- AWS IAM - temporary security credentials (roles) - https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp.html
- Amazon S3 - Block Public Access - https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html
- AWS KMS - rotating keys - https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html
- AWS Secrets Manager - rotating secrets - https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html
- Amazon CloudWatch - overview - https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html

Prof. Happy (SUTA Labs)
