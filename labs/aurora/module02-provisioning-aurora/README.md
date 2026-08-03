# Module 02: Provisioning Aurora (CLI + Console)

**Track:** DevOps DBA Training
**Duration:** ~12 hours
**Week:** 1
**Prerequisites:** Module 01 completed (AWS account, VPC, basic SQL)

---

## What You Will Learn

This module gets you hands-on with a real Aurora cluster. By the end, you will:

- Create an Aurora PostgreSQL cluster via the AWS Console (point and click)
- Create the same cluster via AWS CLI (command line - the DevOps way)
- Understand Aurora endpoints (writer, reader, instance)
- Configure custom parameter groups
- Add read replicas and test read/write splitting
- Know exactly how to clean up everything to avoid surprise charges

---

## Module Contents

### Concepts (read first)
1. [Aurora Cluster Components](concepts/01-aurora-cluster-components.md) - Writer, reader, endpoints, parameter groups, subnet groups
2. [Configuration Management](concepts/02-configuration-management.md) - Parameter groups vs postgresql.conf, managed config patterns

### BUILD (hands-on, follow step by step)
1. [Create Aurora Cluster - Console](build/01-create-aurora-cluster-console.md) - Step-by-step in AWS Console (45 min)
2. [Create Aurora Cluster - CLI](build/02-create-aurora-cluster-cli.md) - Same thing via AWS CLI (45 min)
3. [Configure Parameter Groups](build/03-configure-parameter-groups.md) - Create and apply custom parameters (30 min)
4. [Connect and Verify](build/04-connect-and-verify.md) - Connect with psql, verify endpoints work (20 min)
5. [Add Read Replicas](build/05-add-read-replicas.md) - Add reader instances, test reader endpoint (30 min)
6. [Cleanup and Cost Control](build/06-cleanup-and-cost-control.md) - Proper teardown order, cost tracking (15 min)

### USE (practice with less hand-holding)
1. [Provisioning Practice](use/01-provisioning-practice.md)
2. [Endpoint Routing Exercise](use/02-endpoint-routing-exercise.md)
3. [Parameter Group Exercise](use/03-parameter-group-exercise.md)
4. [Multi-Instance Exercise](use/04-multi-instance-exercise.md)
5. [Cleanup Checklist](use/05-cleanup-checklist.md)

### SURVIVE (chaos scenarios)
1. [Security Group Lockout](survive/01-security-group-lockout/) - Blocked connections
2. [Wrong Endpoint](survive/02-wrong-endpoint/) - App connecting to reader instead of writer
3. [Instance Stopped](survive/03-instance-stopped/) - Aurora instance unexpectedly stopped
4. [Storage Full](survive/04-storage-full/) - Storage auto-scaling disabled

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - Provisioning, endpoints, configuration

---

## Cost Warning

This module creates an Aurora cluster. A db.t3.medium writer instance costs approximately $0.07/hour. With a reader, that is $0.14/hour total. If you leave the cluster running for 24 hours, that is about $3.36.

**Always clean up when you are done practicing.** BUILD 06 walks you through proper cleanup. Run it every time you finish a lab session.

---

## What is Next

After completing this module, you will move to [Module 03: Terraform for Database Infrastructure](../module03-terraform-for-databases/) where you rebuild everything you just did - but as code.
