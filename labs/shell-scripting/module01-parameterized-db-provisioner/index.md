---
layout: default
title: "Module 01 - Parameterized DB Provisioner"
nav_order: 1
---

# Module 01: Parameterized Database Provisioner

Convert a PostgreSQL provisioning SQL script into a reusable, parameterized shell script.

---

## Concepts

| # | Doc | Topic |
|:--|:----|:------|
| C1 | [Shell Scripting Fundamentals](concepts/01-shell-scripting-fundamentals/) | Variables, arguments, exit codes, safety flags |
| C2 | [Functions, Heredocs, and psql](concepts/02-functions-heredocs-and-psql-integration/) | Functions, heredocs, psql integration patterns |

## BUILD Guides

| # | Guide | Topic |
|:--|:------|:------|
| B1 | [Your First Shell Script](build/01-your-first-shell-script/) | Shebang, chmod, variables, quoting |
| B2 | [Command-Line Arguments](build/02-command-line-arguments/) | $1, $2, $#, defaults |
| B3 | [Input Validation and Exit Codes](build/03-input-validation-and-exit-codes/) | if/then, usage(), set -euo pipefail |
| B4 | [Functions](build/04-functions/) | Defining, local vars, main() pattern |
| B5 | [Here Documents](build/05-here-documents/) | Heredoc syntax, variable expansion, psql |
| B6 | [psql Integration Patterns](build/06-psql-integration-patterns/) | -c, -f, -v, idempotent checks, error handling |
| B7 | [Building the Provisioner](build/07-building-the-provisioner/) | Convert the SQL into provision-db.sh |
| B8 | [Testing and Verification](build/08-testing-and-verification/) | Test, verify, idempotency, --dry-run |
