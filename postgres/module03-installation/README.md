# Module 03 - PostgreSQL Installation

How PostgreSQL gets installed, managed, and extended on Linux. Students explore their existing PGDG installation, install a second version alongside, compile from source, and configure extensions.

## BUILD Guides

| Guide | Title | Duration |
|-------|-------|----------|
| 01 | PGDG Repository and Package Anatomy | 30 min |
| 02 | Multi-Version Installation (PG15 alongside PG16) | 45 min |
| 03 | Building PostgreSQL from Source | 60 min |
| 04 | Installing and Configuring Extensions | 45 min |

## USE Exercises

| Exercise | Title | Duration |
|----------|-------|----------|
| 01 | Package Detective | 20 min |
| 02 | Multi-Version Management | 25 min |
| 03 | Source vs Package | 20 min |
| 04 | Extension Workshop | 30 min |
| 05 | Installation Troubleshooting | 25 min |

## SURVIVE Scenarios

| Scenario | Title | Severity |
|----------|-------|----------|
| 01 | Missing Shared Library | CRITICAL |
| 02 | Wrong PG Binary in PATH | MEDIUM |
| 03 | Broken PGDG Repository | MEDIUM |
| 04 | Shared Preload Typo | CRITICAL |
| 05 | PG15 Port Conflict | HIGH |
| 06 | Missing Extension Package | MEDIUM |
| 07 | initdb Wrong Locale | HIGH |
| 08 | Systemd Unit Broken | CRITICAL |

## Topics

- PGDG repository and RPM package structure
- Multi-version installation and management
- Source compilation (configure, make, install)
- Extensions (pg_stat_statements, pgcrypto, pg_trgm, pageinspect)
- shared_preload_libraries
- systemd service management
- PATH and alternatives system

## Prerequisites

- CentOS Stream 9 with PostgreSQL 16 installed (from backup-pitr lab)
- Single node (NODE1 only)

## Status

Built - pending live server validation.
