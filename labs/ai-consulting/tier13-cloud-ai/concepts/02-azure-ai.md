# Concepts 13.2: Azure AI

**Tier 13 - Cloud AI platforms.** A teaching reference for the second major cloud. AWS is your primary; Azure is the one you must understand well enough to recommend when it is the right fit and to compare honestly when a client asks. Many enterprises - especially those already deep in Microsoft (Office 365, Windows, Active Directory) - default to Azure, and you will meet them.

**Who this is for:** you now know the AWS AI stack from Concepts 13.1. This document teaches Azure mostly by mapping each Azure service to the AWS service you already understand, then noting where Azure genuinely differs. Learn one cloud deeply and the rest become translation.

---

## 1. Why a client would choose Azure

- **Microsoft ecosystem gravity.** If the client runs Microsoft 365, uses Entra ID (formerly Azure Active Directory) for all their logins, and buys everything through their Microsoft enterprise agreement, Azure is the path of least resistance - identity, billing, and support are already in place.
- **The OpenAI relationship.** Azure hosts OpenAI's models (GPT family) as a first-party managed service. A client who specifically wants GPT models inside their own cloud boundary, under enterprise terms and compliance, often lands on Azure for that reason.
- **Compliance posture.** Azure has deep government and regulated-industry certifications and offerings, which matters for public-sector and financial clients.

The consultant point: the "best" cloud is frequently the one the client already runs. Do not move an all-Microsoft shop to AWS to satisfy your own preference - meet them where they are, and reduce lock-in through your own abstraction layer instead.

---

## 2. The AWS-to-Azure map

Keep this table in your head. It lets you talk to an Azure client fluently on day one.

| Need | AWS | Azure |
|---|---|---|
| Hosted foundation models | Bedrock | **Azure OpenAI** / **Azure AI Foundry** |
| Broader AI/ML platform | SageMaker | **Azure Machine Learning** |
| Prebuilt AI capabilities (vision, speech, language) | (Bedrock + others) | **Azure AI services** (formerly Cognitive Services) |
| Identity and access | IAM | **Entra ID** + RBAC |
| Secrets and keys | Secrets Manager + KMS | **Azure Key Vault** |
| Object storage | S3 | **Azure Blob Storage** |
| Serverless functions | Lambda | **Azure Functions** |
| Containers | ECS/EKS | **Azure Container Apps** / **AKS** |
| Private network | VPC | **Virtual Network (VNet)** |
| Private service access | VPC endpoint / PrivateLink | **Private Endpoints** |
| Monitoring and alarms | CloudWatch | **Azure Monitor** + **Application Insights** |
| Safety filtering | Bedrock Guardrails | **Azure AI Content Safety** |

If you can read this table both directions, you can hold a design conversation in either cloud.

---

## 3. Azure OpenAI and AI Foundry

**Azure OpenAI Service** gives you OpenAI's models (GPT and related) as a managed Azure service. You create a **deployment** of a specific model in your Azure resource, and call it through an endpoint tied to your Azure identity. The data-handling story is the Azure enterprise one - Microsoft states your prompts and completions are **not** used to train or improve the OpenAI or Microsoft models and are not shared with OpenAI, and everything stays under your Azure agreement (see: https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy). This is the Azure equivalent of Bedrock, specialized around OpenAI models.

**Azure AI Foundry** (the newer umbrella, evolving from what was called Azure AI Studio) is the workbench for building, evaluating, and deploying AI applications on Azure - model catalog, prompt tooling, evaluation, and deployment in one place. Think of it as the console and SDK surface for building on Azure's models, broader than just OpenAI (its model catalog spans Microsoft, OpenAI, Anthropic, Meta, Mistral, Cohere, NVIDIA, and more; see: https://learn.microsoft.com/en-us/azure/ai-foundry/what-is-azure-ai-foundry). Under this umbrella, Azure OpenAI is now presented as "Azure OpenAI in Foundry Models."

Consultant note: naming in this space churns hard. "Cognitive Services" became "Azure AI services" (and is being folded into the Foundry branding), "Azure AI Studio" became "Azure AI Foundry", and Microsoft has continued to rebrand the umbrella - always confirm the current product name in the Microsoft docs before you write it into a client deliverable. Speak in capabilities ("we need a hosted GPT deployment with a private endpoint") rather than clinging to a product name, because the name may have changed by the time you deliver.

---

## 4. Azure Machine Learning

**Azure Machine Learning (Azure ML)** is the SageMaker equivalent: the full platform for training, tuning, tracking, and hosting your own models. Same guidance as on AWS - most "we just need an LLM feature" engagements do not need it. Reach for it only when the client trains custom models or self-hosts open-weight models.

---

## 5. Identity: Entra ID and RBAC

**Entra ID** (formerly Azure Active Directory) is Azure's identity service. If the client already uses it for Microsoft 365 logins, their identities are already there - a real advantage for single sign-on. Azure's permission model is **RBAC (role-based access control)**: you assign roles (built-in or custom) to identities at a scope (a resource, a resource group, or the whole subscription).

The same discipline as AWS IAM applies: least privilege, prefer **managed identities** (Azure's equivalent of assumable roles - an identity attached to the app so it needs no stored credentials) over stored secrets, and never wildcard sensitive permissions. The IAM lessons transfer directly; only the vocabulary changes.

---

## 6. Secrets and keys: Key Vault

**Azure Key Vault** combines what AWS splits between Secrets Manager and KMS: it stores secrets, keys, and certificates, controls access through Entra ID, and supports rotation. Your app reads its secrets from Key Vault at runtime using its managed identity - same principle as before, nothing hardcoded. And the same failure mode applies: if the app assumes a key or secret never changes, a rotation will break it, which is why rotation must be designed for, not bolted on.

---

## 7. Network and privacy: VNet and Private Endpoints

A **Virtual Network (VNet)** is Azure's VPC. **Private Endpoints** are Azure's way to reach a managed service (like Azure OpenAI) over the Microsoft backbone instead of the public internet - the direct analog of an AWS VPC endpoint. Regulated clients will require that the model endpoint is private and not exposed publicly. The design pattern is identical to AWS: app in a private subnet, model reached over a private endpoint, tight network rules.

---

## 8. Safety: Content Safety

**Azure AI Content Safety** is the Guardrails analog: a service that screens text and images for harmful content across categories (hate, sexual, violence, self-harm) with configurable severity thresholds. It also includes **Prompt Shields** (detection of direct *and* indirect prompt-injection attacks) and **groundedness detection** (see: https://learn.microsoft.com/en-us/azure/ai-services/content-safety/overview). You place it in front of your model calls the same way you place a Bedrock Guardrail. The concept is the same; the knobs and category names differ.

---

## 9. Observability: Azure Monitor and Application Insights

**Azure Monitor** collects metrics and logs; **Application Insights** adds application-level tracing. Together they are the CloudWatch analog. You watch token usage, latency, and error rates, and you set **alerts** (the alarm analog) that fire on anomalies such as a cost or volume spike. Same discipline: you must be paged before the bill explodes, not after.

---

## 10. The consultant's summary

- Azure is often the right recommendation for Microsoft-centric and Entra-ID clients, and for clients who specifically want OpenAI models in their own boundary.
- Every AWS service you learned has an Azure twin - learn the map, speak either cloud.
- The security discipline is identical: managed identities over secrets, least-privilege RBAC, private endpoints, Key Vault for secrets and keys, Content Safety in front, alerts on cost.
- Names in Azure AI change often - talk capabilities, not product names.
- Keep model calls behind your own abstraction so a client on Azure OpenAI today can still move tomorrow. Lock-in is a design choice, and you choose against it.

---

## References

- Azure AI Foundry - what it is (workbench + multi-provider model catalog) - https://learn.microsoft.com/en-us/azure/ai-foundry/what-is-azure-ai-foundry
- Azure OpenAI - data privacy (prompts/completions not used to train base models) - https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/openai/data-privacy
- Azure AI Content Safety - overview (harm categories, Prompt Shields, groundedness) - https://learn.microsoft.com/en-us/azure/ai-services/content-safety/overview
- Microsoft Entra ID (formerly Azure Active Directory) - name change - https://learn.microsoft.com/en-us/entra/fundamentals/new-name
- AWS to Azure service comparison - https://learn.microsoft.com/en-us/azure/architecture/aws-professional/services
- Azure managed identities - overview - https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview

Prof. Happy (SUTA Labs)
