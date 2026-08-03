# Module 10 - Use Exercise 01: Architecture Review

**Objective:** Conduct a peer review of the complete Aurora stack architecture. Evaluate the design decisions, identify gaps, and produce a written review document.
**Time:** 30 minutes
**Level:** Senior / Staff

---

## Context

You have built a production Aurora PostgreSQL stack across Build Guides 01-08. Now step back and review the architecture as if you are a senior engineer or architect evaluating someone else's work. The goal is to find gaps, over-engineering, and missed requirements.

---

## Exercise

<details>
<summary>Part 1: Network Architecture Review (click to expand)</summary>

Review the VPC configuration and answer these questions in writing.

### Questions

1. **Subnet sizing:** The design uses /24 subnets (251 usable IPs each). Is this sufficient? What if the company grows to 500 microservices, each needing database access?

2. **AZ distribution:** The design uses 3 AZs for database subnets but only 2 AZs for application subnets. What is the impact if the application in AZ-a needs to reach a reader in AZ-c?

3. **VPC endpoints:** The design includes 4 interface endpoints. At roughly $7.50/month each, is this cost justified? Which endpoints could you remove if cost is a concern?

4. **NAT gateway HA:** Two NAT gateways are deployed. What happens if you reduce to one? What is the cost savings vs availability tradeoff?

5. **Cross-AZ traffic:** Aurora automatically routes traffic to the instance closest to the caller. Are there cross-AZ data transfer charges? How significant are they?

### Expected Answers

1. /24 provides 251 IPs per subnet. For DB subnets, Aurora uses very few IPs (2-3 per instance + ENIs for endpoints). /24 is overkill but does not cost extra. For app subnets, 251 IPs may be insufficient with 500 services - consider /22 (1,019 IPs) if growth is expected.

2. Cross-AZ latency adds approximately 1ms. This is negligible for most workloads. The bigger concern is cross-AZ data transfer cost ($0.01/GB). For read-heavy workloads, deploy readers in every AZ that has application servers.

3. S3 gateway endpoint is free. The 3 interface endpoints cost approximately $22.50/month. The monitoring endpoint is critical (Enhanced Monitoring). The logs endpoint is critical (CloudWatch Logs export). Secrets Manager endpoint is critical (password retrieval). All are justified for a production cluster.

4. Single NAT gateway saves approximately $32/month. If it goes down, all app subnets lose internet access. For production, keep two. For staging/dev, one is acceptable.

5. Yes, cross-AZ data transfer is $0.01/GB per direction. For a cluster doing 10 GB/day of cross-AZ traffic, that is approximately $6/month. Not significant for most workloads.

</details>

<details>
<summary>Part 2: Security Review (click to expand)</summary>

### Questions

1. **Least privilege:** The application uses the `app_service` database role. Review the grants from Build 05. Can this role ALTER or DROP tables? Should it be able to?

2. **Master password:** The master password is managed by Secrets Manager. Who can access this secret? Is the access scope too broad?

3. **Security group rules:** The Aurora SG allows traffic from the app SG and bastion SG. Should there be any other sources? What about a monitoring tool like Datadog?

4. **KMS key policy:** The CMK is used for storage encryption. Who has `kms:Decrypt` access? If the key is compromised, what is the blast radius?

5. **pgaudit scope:** The configuration logs `ddl,role,write`. Is this sufficient? Should `read` operations also be logged? What is the performance impact?

### Expected Answers

1. `app_service` has SELECT, INSERT, UPDATE, DELETE. No ALTER, DROP, or TRUNCATE. This is correct - the application should never modify schema. Schema changes go through the CI/CD pipeline.

2. Secrets Manager access is controlled by the IAM policy on the RDS service role. Review who has `secretsmanager:GetSecretValue` access. The GitHub Actions role also has access - ensure it is scoped to the specific secret ARN, not `*`.

3. If using Datadog or similar, add a separate SG rule for the monitoring agent's security group. Do NOT open a CIDR range for SaaS monitoring tools - use a PrivateLink connection instead.

4. KMS key policy should restrict `kms:Decrypt` to the RDS service, the admin role, and the DR restore role. If compromised, all data at rest is potentially exposed. Enable CloudTrail key usage logging.

5. Logging `read` operations significantly increases log volume (every SELECT is logged). For most applications, `ddl,role,write` is sufficient. Enable `read` only for databases with strict compliance requirements (PCI-DSS, HIPAA).

</details>

<details>
<summary>Part 3: Availability Review (click to expand)</summary>

### Questions

1. **Single-region design:** This stack runs in us-east-1 only. Cross-region DR uses snapshot restore. Is a 2-4 hour RTO acceptable? When would you need Aurora Global Database instead?

2. **Failover testing:** The chaos testing in Build 08 tested forced failover. What about unplanned failure modes that chaos testing did not cover?

3. **Connection handling:** The architecture document specifies retry logic. Is there a connection pooler (RDS Proxy, PgBouncer) in the architecture? Should there be?

4. **Maintenance risk:** The maintenance window is Sunday 3-4 AM UTC. What if a critical zero-day patch needs to be applied during business hours?

5. **Reader scaling:** The design starts with 1 reader. What triggers adding a second reader? Is there auto-scaling configured?

### Expected Answers

1. 2-4 hour RTO is acceptable for most non-financial applications. Use Aurora Global Database when RTO must be under 1 minute for cross-region failover. Global Database adds complexity and cost.

2. Untested: network partition between AZs, DNS resolution failure, KMS key unavailability, IAM service degradation. These are rare but should be documented in the risk register.

3. No connection pooler is deployed. For production with microservices, RDS Proxy is strongly recommended - it reduces connection churn, handles failover more gracefully, and supports IAM auth.

4. Emergency patches bypass the maintenance window. Use `--apply-immediately` and coordinate with the application team. Document this in the runbook as "emergency maintenance procedure."

5. Add a second reader when: (a) read latency increases above baseline, (b) CPU on the reader exceeds 70%, or (c) the application adds a new read-heavy feature. Aurora Auto Scaling can automate this based on CPU or connections.

</details>

<details>
<summary>Part 4: Cost Review (click to expand)</summary>

### Questions

1. **Instance sizing:** The design uses db.r6g.large for both writer and reader. What metrics would trigger a scale-up to db.r6g.xlarge?

2. **Reserved Instances:** The cost estimate shows On-Demand pricing. At what point should you purchase Reserved Instances?

3. **Storage type:** The design starts with Aurora Standard. What specific metric would trigger evaluation of I/O-Optimized?

4. **Development cost:** Is there a staging cluster? What is the cost of maintaining a staging environment that mirrors production?

5. **Hidden costs:** What costs are not in the estimate? (Hint: data transfer, snapshot storage, CloudWatch)

### Expected Answers

1. Scale up when: average CPU > 70% for a week, freeable memory < 1 GB consistently, or Performance Insights shows db.load exceeding vCPU count.

2. Purchase RIs after the cluster has been stable for 1-2 months. Ensure the instance class will not change soon. Start with 1-year No Upfront for flexibility.

3. Check Cost Explorer for `Aurora:StorageIOUsage` line item. If it exceeds 25% of total Aurora spend, run the I/O-Optimized calculation.

4. A staging cluster with the same instance classes costs approximately $350/month. Consider using smaller instances (db.t3.medium) for staging to reduce cost while maintaining compatibility.

5. Hidden costs: cross-AZ data transfer ($0.01/GB), CloudWatch Logs ingestion ($0.50/GB), SNS notifications ($0.50/million), VPC endpoint hours ($7.50/endpoint/month), KMS API calls ($0.03/10,000).

</details>

---

## Deliverable

Write a 1-page architecture review document summarizing:

1. **Strengths** - What is well-designed
2. **Gaps** - What is missing or under-specified
3. **Recommendations** - Specific changes with priority (P1/P2/P3)
4. **Risk register** - Failure modes not covered by the current design

This review document would be presented in a real architecture review meeting.

---

## Summary

Architecture review is a critical skill for senior engineers. The ability to evaluate a design, identify gaps, and recommend improvements is what separates a builder from an architect. Practice this exercise on every production system you work with.
