# Module 03: Terraform for Database Infrastructure

**Track:** DevOps DBA Training
**Duration:** ~14 hours
**Week:** 2
**Prerequisites:** Module 01 + Module 02 completed (AWS account, VPC, Aurora cluster experience)

---

## What You Will Learn

This is the module that transforms you from a console-clicker into an Infrastructure as Code practitioner. By the end, you will:

- Understand why IaC matters and how it changes database operations
- Install and use Terraform (init, plan, apply, destroy cycle)
- Provision a complete Aurora PostgreSQL cluster using Terraform
- Use modules and remote state for team-friendly infrastructure
- Import existing resources into Terraform state
- Know when to use `prevent_destroy` and lifecycle rules

---

## Module Contents

### Concepts (read first)
1. [Infrastructure as Code](concepts/01-infrastructure-as-code.md) - Why IaC, Terraform vs alternatives, declarative vs imperative
2. [Terraform for DBAs](concepts/02-terraform-for-dbas.md) - DBA-specific patterns, parameter groups as code, security groups as code

### BUILD (hands-on, follow step by step)
1. [Terraform Install and Basics](build/01-terraform-install-and-basics.md) - Install, init, plan, apply cycle (45 min)
2. [Provision Aurora with Terraform](build/02-provision-aurora-with-terraform.md) - Full Aurora cluster in HCL (60 min)
3. [Modules and State](build/03-modules-and-state.md) - Terraform modules, remote state, locking (45 min)
4. [Aurora Advanced Patterns](build/04-aurora-advanced-patterns.md) - Loops, conditionals, data sources (45 min)
5. [Terraform Import](build/05-terraform-import-existing.md) - Import manually-created resources (30 min)
6. [Destroy and Lifecycle](build/06-terraform-destroy-and-lifecycle.md) - Safe destruction, prevent_destroy, lifecycle rules (20 min)

### USE (practice with less hand-holding)
1. [Terraform Workflow Exercise](use/01-terraform-workflow-exercise.md)
2. [Write Aurora Module](use/02-write-aurora-module.md)
3. [State Management Exercise](use/03-state-management-exercise.md)
4. [Import Exercise](use/04-import-exercise.md)
5. [Code Review Exercise](use/05-code-review-exercise.md)

### SURVIVE (chaos scenarios)
1. [State File Disaster](survive/01-state-file-disaster/) - State file corrupted or deleted
2. [Accidental Destroy](survive/02-accidental-destroy/) - terraform destroy hits production
3. [Drift Detection](survive/03-drift-detection/) - Manual changes made outside Terraform

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - Terraform, IaC, state management

---

## Cost Warning

This module creates and destroys Aurora clusters via Terraform. Same costs as Module 02 - approximately $0.14/hour for writer + reader. Terraform makes it easy to create AND easy to destroy, so always run `terraform destroy` when done.

---

## What is Next

After completing this module, you will move to [Module 04: Aurora Security and IAM](../module04-aurora-security-iam/) where you secure your Aurora cluster using IAM policies, encryption, and network security.
