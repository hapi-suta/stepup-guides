# Demo: Cross-Column Email Uniqueness in PostgreSQL

## The Business Rule

| Scenario | Allowed? |
|----------|----------|
| Row 1: primary = secondary (same row) | YES |
| Same email appears in two different rows (any column) | NO |

## How It Works

A `BEFORE INSERT OR UPDATE` trigger checks every write:

1. **Primary email** — must not exist in any other row's primary or secondary column
2. **Secondary email** — same rule, *unless* it equals the primary on the same row (same-row duplicate is explicitly permitted)

No application-level logic required. The database enforces it.

## Files

| File | Purpose |
|------|---------|
| `setup.sql` | Creates the table + trigger. Run once. |
| `run_tests.sql` | 9 labelled test cases with expected outcomes |
| `run_demo.sh` | One-command runner (setup + tests) |

## Quick Start

### Option A — One command (bash)
```bash
bash run_demo.sh [dbname] [user]
# defaults: postgres / postgres
```

### Option B — Manual (psql)
```sql
\i setup.sql
\i run_tests.sql
```

## Test Matrix

| # | What is being tested | Expected |
|---|----------------------|----------|
| 1 | Normal insert, distinct emails | PASS |
| 2 | primary = secondary, same row | PASS |
| 3 | New row — secondary steals another row's primary | FAIL |
| 4 | New row — primary steals another row's secondary | FAIL |
| 5 | New row — reuses a primary=secondary email from another row | FAIL |
| 6 | Both columns conflict simultaneously | FAIL |
| 7 | Fully unique emails | PASS |
| 8 | UPDATE: a row changes its own secondary to a new email | PASS |
| 9 | UPDATE: a row tries to steal another row's email | FAIL |

## Why not a UNIQUE index?

A `UNIQUE` index on a single column only enforces uniqueness within that column.
There is no built-in constraint in PostgreSQL that spans two columns with this
asymmetric rule (same-row exception). The trigger is the correct tool here.

## Performance Note

For large tables, add indexes to support the trigger's existence checks:

```sql
CREATE INDEX idx_contacts_primary_email   ON contacts(primary_email);
CREATE INDEX idx_contacts_secondary_email ON contacts(secondary_email);
```

These turn the trigger's `EXISTS` queries from seq scans into index lookups.
