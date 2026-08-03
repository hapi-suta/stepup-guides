# AWS RDS and Aurora PostgreSQL - CBUSI Track

From novice to master in managed PostgreSQL on AWS. Covers both RDS for PostgreSQL and Aurora PostgreSQL.

## Track Structure

Each tier follows the CBUSI methodology:
- **C** - Concepts: mental models and reference material
- **B** - Build: step-by-step guided labs (CLI + Console)
- **U** - Use: realistic exercises with less hand-holding
- **S** - Survive: chaos scenarios with inject/runbook/validate
- **I** - Interview: graduated questions (Junior through Principal)

## Tiers

| Tier | Name | Level | Topics | Survive |
|------|------|-------|--------|---------|
| 0 | Foundations | Novice | 5 | No |
| 1 | Provisioning and Connectivity | Beginner | 5 | Yes |
| 2 | Security and Access | Beginner-Intermediate | 6 | Yes |
| 3 | Configuration and Extensions | Intermediate | 7 | Yes |
| 4 | Availability and Replication | Intermediate | 7 | Yes |
| 5 | Backup, Recovery, and Lifecycle | Intermediate-Advanced | 6 | Yes |
| 6 | Performance and Monitoring | Advanced | 12 | Yes |
| 7 | Scaling, Integration, and Modern Patterns | Advanced-Expert | 6 | Yes |
| 8 | Operations at Scale and Mastery | Expert-Master | 9 | Yes |
| Cap | [Capstone Project](capstone/) | All levels | 7 phases | Scored |

## Prerequisites

- An AWS account (students use their own accounts)
- AWS CLI v2 installed
- Basic comfort with the terminal
- No prior AWS knowledge required (Tier 0 covers everything)
- Review the [Cost Estimation Guide](COST-GUIDE.md) before starting (especially on personal accounts)

## Infrastructure

Students provision all resources in their own AWS accounts. Every lab that creates billable resources includes a cleanup section. Labs use Free Tier eligible resources where possible.

## Engine Scope

Labs explicitly call out when RDS and Aurora behavior differs. Students learn both engines side by side.

## Content Summary

- **275 files** across 9 tiers + capstone
- **63 BUILD guides** (CLI + AWS Console steps)
- **46 USE exercises** with realistic scenarios
- **37 SURVIVE chaos scenarios** (inject.sh + runbook.md + validate.sh)
- **9 interview question sets** graduated Junior through Principal
- **9 concepts reference docs** with ASCII diagrams and comparison tables

## Status

| Tier | Concepts | Build | Use | Survive | Interview |
|------|----------|-------|-----|---------|-----------|
| 0 | Done | 5 guides | 5 exercises | N/A | Done |
| 1 | Done | 5 guides | 5 exercises | 4 scenarios | Done |
| 2 | Done | 6 guides | 5 exercises | 4 scenarios | Done |
| 3 | Done | 7 guides | 5 exercises | 4 scenarios | Done |
| 4 | Done | 7 guides | 5 exercises | 5 scenarios | Done |
| 5 | Done | 6 guides | 5 exercises | 5 scenarios | Done |
| 6 | Done | 12 guides | 6 exercises | 6 scenarios | Done |
| 7 | Done | 6 guides | 5 exercises | 4 scenarios | Done |
| 8 | Done | 9 guides | 5 exercises | 5 scenarios | Done |
