---
layout: default
title: "Module 01 - Architecture and Oracle Bridge"
nav_order: 2
has_children: true
---

# Module 01 - EPAS Architecture and the Oracle Bridge

Lock in the mental model for EDB Postgres Advanced Server (EPAS) before you ever touch a server. If you are coming from Oracle, this is the most important module in the track - because if your Oracle reflexes are not remapped to EPAS equivalents, you will spend the next seven modules confused about why things work the way they do.

## Mode

Theory only - no server required. Work through this entire module on your laptop while your EPAS lab environment is being provisioned in week 1.

## Audience

Oracle DBAs (3-5+ years) being asked to manage EPAS in production. Assumes you know Oracle internals (SGA, redo, archive, RMAN, Data Guard, OEM) but know nothing about PostgreSQL or EPAS.

## Progress

Content is released one phase at a time. Complete each phase and pass the quiz with Prof. Happy on WhatsApp to unlock the next one.

| # | Phase | Title | Time | Status |
|:--|:------|:------|:-----|:-------|
| 01 | [Concepts](concepts/01-postgres-and-edb-story/) | Postgres history and the EDB story | 45 min | Available |
| 02 | [Concepts](concepts/02-epas-architecture/) | EPAS architecture deep dive | 60 min | Available |
| 03 | [Concepts](concepts/03-oracle-to-epas-bridge/) | Oracle to EPAS bridge (the killer doc) | 90 min | Available |
| 01 | [Build](build/01-architecture-walkthrough/) | Architecture deep dive walkthrough | 60 min | Available |
| 02 | [Build](build/02-oracle-epas-mapping-worksheet/) | Oracle to EPAS production scenarios | 90 min | Available |
| 01 | [Use](use/01-production-scenario-analysis/) | Production scenario analysis (6 scenarios) | 90 min | Available |
| 01 | [Survive](survive/01-architecture-diagnosis-scenarios/) | Architecture diagnosis scenarios | 60 min | Available |
| 01 | [Interview](interview/01-architecture-interview-prep/) | Architecture interview prep (15 questions) | 45 min | Available |

**Total time:** 8-9 hours over week 1.

## Slide Deck

Prefer reading as a presentation? View the full Module 01 slide deck (49 slides) on GitHub:

**[View EPAS_Module01_SUTA.pptx](https://github.com/hapi-suta/laas-linuel-edb/blob/main/assets/downloads/EPAS_Module01_SUTA.pptx)**

## How to Use

1. Start with the 3 Concepts docs in order (01 -> 02 -> 03)
2. Do NOT skip Concepts 03. The Oracle bridge doc is the single most important document in this entire track. Read it twice. Print it.
3. Keep Concepts 03 (Oracle bridge) open as a tab for the entire 8-week track
4. When you finish Concepts, message Prof. Happy on WhatsApp - he will quiz you and unlock the Build phase

## What Success Looks Like

By the end of this module, when someone says "we need to set up Data Guard between two EPAS instances," you can immediately think "EFM" and know roughly what that means. When someone says "RMAN-equivalent backup," you think "Barman." When you see "PL/SQL with packages," you do not panic - you know EPAS supports it natively via edb-spl. When you get a 2am page about disk space, you know to check pg_wal/ first.
