# Tier 0 - Foundations

**Level:** Novice
**Infrastructure:** None required (conceptual + AWS Console exploration)
**Estimated Time:** 3-4 hours total

## Overview

Build the mental models you need before touching a managed database. By the end of this tier, you will understand what AWS manages vs what you manage, how RDS and Aurora differ architecturally, and have enough networking and PostgreSQL knowledge to provision your first instance in Tier 1.

## Topics

| ID | Topic | Build | Use | Interview |
|----|-------|-------|-----|-----------|
| T0.1 | Managed databases and shared responsibility | 01 | 01 | Yes |
| T0.2 | RDS vs Aurora architecture | 02 | 02 | Yes |
| T0.3 | AWS account, IAM, regions, and AZs | 03 | 03 | Yes |
| T0.4 | VPC networking for databases | 04 | 04 | Yes |
| T0.5 | PostgreSQL refresher | 05 | 05 | Yes |

## Content

- `concepts/foundations.md` - Reference document covering all 5 topics
- `build/01-05` - Step-by-step guided labs (CLI + AWS Console)
- `use/01-05` - Practical exercises with realistic scenarios
- `interview/tier0-interview-questions.md` - 44 graduated interview questions

## No Survive Phase

Tier 0 is conceptual. Survive (chaos) scenarios begin in Tier 1 when students have live infrastructure to break.

## Next

After completing Tier 0, proceed to [Tier 1 - Provisioning and Connectivity](../tier1-provisioning/).
