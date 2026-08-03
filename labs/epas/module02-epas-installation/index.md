---
layout: default
title: "Module 02 - EPAS 16 Installation"
nav_order: 3
has_children: true
---

# Module 02 - EPAS 16 Installation

Your first hands-on module. Module 01 gave you the mental model; now you get a real CentOS server and build a running EPAS 16 database on it from scratch - repo, packages, initdb, service, first login - the exact sequence you would run if the CardAuth migration project handed you a fresh VM at Mastercard.

## Mode

Hands-on - you need your lab server. Prof. Happy provisions it and sends your connection details and EDB repo token on WhatsApp when you start this module.

## Audience

Oracle DBAs who completed Module 01. You know the EPAS process model, memory, WAL, and storage layout in theory. Now you touch all of it.

## Progress

Content is released one phase at a time. Complete each phase and pass the quiz with Prof. Happy on WhatsApp to unlock the next one.

| # | Phase | Title | Time | Status |
|:--|:------|:------|:-----|:-------|
| 01 | [Concepts](concepts/01-edb-repos-and-packaging/) | EDB repos, packaging, and how EPAS ships | 45 min | Available |
| 02 | [Concepts](concepts/02-clusters-initdb-and-the-redwood-decision/) | Clusters, initdb, and the Redwood decision | 60 min | Available |
| 01 | [Build](build/01-install-epas-16/) | Install EPAS 16 | 60 min | Available |
| 02 | [Build](build/02-first-tour-for-oracle-dbas/) | First tour for an Oracle DBA | 60 min | Available |
| 01 | [Use](use/01-installation-decision-scenarios/) | Installation decision scenarios (5 scenarios) | 60 min | Available |
| 01 | [Survive](survive/01-installation-failure-scenarios/) | Installation failure scenarios (4 incidents) | 60 min | Available |
| 01 | [Interview](interview/01-installation-interview-prep/) | Installation interview prep (15 questions) | 45 min | Available |

**Total time:** 6-7 hours over week 1.

## How to Work Through This

1. Read the 2 Concepts docs in order - Concepts 02 explains a decision in Build 01 that you cannot undo
2. Message Prof. Happy when you finish Concepts - he will quiz you, provision your server, send your EDB token, and unlock Build
3. Work Build 01 end to end on your server - every command has its real expected output shown
4. Work Build 02 - the day-one tour and the 5-point health checklist you will use for the rest of the track
5. Use and Survive apply what you built to production incidents - unlocked after the Build quiz
6. Finish with Interview prep - say the answers out loud, not in your head
7. The one rule for this module: never run a command as the wrong user. When in doubt, `whoami`

## What Success Looks Like

You can take a bare CentOS server and produce a running, Redwood-mode EPAS 16 cluster in under 30 minutes, verify it with the 5-point health checklist, and explain to an Oracle DBA exactly which of their reflexes transfer and which three will burn them (port 5444, user enterprisedb, database edb).

## Support

- **WhatsApp**: Message Prof. Happy anytime
- **Email**: [afopzhappy@gmail.com](mailto:afopzhappy@gmail.com)
