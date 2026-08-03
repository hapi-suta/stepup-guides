# pgForge Project 1: Git - PostgreSQL Operations Source of Truth

Build **pg-ops** - the versioned home for every config template, script, and runbook you own. Git is PITR for your files: every commit is a restore point.

**Environment:** your Mac + one CentOS Stream 9 server (t3.small) running a REAL PostgreSQL 16 cluster whose configs you version-control.
**Time:** 2-3 weeks at 10 hrs/week.
**Follows:** CBUSI (Concepts, BUILD, USE, SURVIVE, Interview).

## Phases

| Phase | File | Time |
|-------|------|------|
| Concepts | `concepts/01-git-for-dbas.md` | 20 min |
| BUILD 0 | `build/00-server-and-cluster.md` - real PG16 cluster on CentOS | 45 min |
| BUILD 1 | `build/01-repo-and-scanner.md` - repo + secret scanner (Mac) | 40 min |
| BUILD 2 | `build/02-version-the-real-config.md` - pull the server's REAL configs, baseline commit | 40 min |
| BUILD 3 | `build/03-change-reload-verify.md` - tune in repo, push to server, reload vs restart live | 45 min |
| BUILD 4 | `build/04-branch-pr-tag.md` - branch, PR, tag | 45 min |
| USE | `use/01-judgment-exercises.md` | 60 min |
| SURVIVE 1 | `survive/01-revert-bad-change.md` | 30 min |
| SURVIVE 2 | `survive/02-credential-leak.md` | 45 min |

## Important Notes from Testing

Git commands tested on Happy's MacBook Pro; server commands tested on a live t3.small CentOS Stream 9 with PostgreSQL 16.11 (PGDG), 2026-07-22. git 2.50.1, gitleaks 8.30.1, gh 2.83.2. Full captured output: `test-results.txt` (56 steps PASS).

- **Reload vs restart, proven live:** after `systemctl reload`, work_mem changed but shared_buffers stayed at 128MB with `pending_restart = t` in pg_settings; only restart applied it. The `pending_restart` query is in Build 3 - use it before and after every config deployment.
- **ec2-user cannot read postgresql.conf** (postgres owns it, mode 600). Pull with `ssh ... 'sudo cat ...' > localfile`; push back with `... | ssh ... 'sudo tee ...'` - tee keeps the file owned by postgres.

- **gitleaks allowlists AWS's documented example keys.** `AKIAIOSFODNN7EXAMPLE` commits cleanly with "no leaks found". To prove the scanner works, use a realistic token pattern (a fake `ghp_...` GitHub token gets blocked with `leaks found: 1`, exit 1).
- **git-filter-repo removes the `origin` remote on purpose** after a purge. You must `git remote add origin ...` again and force push. The guide covers this.
- **filter-repo rewrites commit IDs.** After the purge, the same revert commit changed from `1acdd71` to `cb4c398`. Old IDs in your notes stop matching - expected.
- **Git does not track empty directories.** After the leaked file was purged, its `scripts/` folder disappeared entirely.
- **The gitleaks banner prints on every commit.** The little ASCII art plus "no leaks found" is normal, not an error.
- **`gh repo delete` needs an extra permission** (`delete_repo` scope) that the default gh login does not have. Test repos must be deleted in the GitHub web UI, or run `gh auth refresh -h github.com -s delete_repo` once.

## Done when

- [ ] github.com/hafopezi10/pg-ops is public with a README explaining the layout
- [ ] Scanner proven: a realistic fake token is BLOCKED (you watched exit 1)
- [ ] At least 2 sanitized templates + 1 runbook + 1 decision doc, all landed via PRs
- [ ] v1.0.0 tag pushed
- [ ] SURVIVE 1 done and timed (write the number down)
- [ ] SURVIVE 2 postmortem committed
- [ ] Concepts checkpoint answerable from memory
- [ ] One final AI-assisted PR (ask Claude to improve your README) with YOUR written review notes on its output
