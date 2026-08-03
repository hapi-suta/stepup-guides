# Research Brief: Project 1 - Git for Database Operations

Researched 2026-07-22, before guide testing. Sources at bottom.

## Standards this lab follows (validated)

1. **git-filter-repo is GitHub's officially recommended tool** for removing sensitive data from history (not BFG, not filter-branch). GitHub's own removal procedure is exactly what SURVIVE 2 teaches: rewrite locally with git-filter-repo, update GitHub with the rewritten history, coordinate with anyone who cloned.
2. **Rotate the secret FIRST.** GitHub's docs state it directly: before any history rewrite, "revoke and/or rotate that secret." SURVIVE 2 teaches rotation-first. Confirmed as the standard, not just our preference.
3. **gitleaks `protect --staged` in a pre-commit hook is the 2026 standard pattern** for local secret scanning. The layered standard is: pre-commit hook (catches ~95% during normal work) + the same scan in CI on every PR + GitHub push protection as the server-side backstop. This lab builds layer 1; Project 8 (CI/CD) adds layer 2.
4. **Known side effects of filter-repo** (from GitHub docs): removes commit/tag signatures on rewritten commits; open PRs should be merged or closed before a rewrite; every collaborator must re-clone. Solo repo = low impact, but the guide states them.
5. **Conventional commit prefixes** (feat:, fix:, perf:, chore:, docs:) match Happy's existing global standard.

## Gap the research caught (now in the guides)

- **Scan existing history BEFORE adding the hook.** The hook only checks new commits. When importing existing scripts/templates, run `gitleaks detect` once against the whole repo history first - already-committed secrets persist even if the files were later deleted. Added to Build 1.

## Context worth knowing

- GitGuardian's March 2026 State of Secrets Sprawl: ~29 million secrets found on public GitHub; **AI-assisted commits leaked secrets at roughly twice the human baseline.** For an AI-assisted workflow like Happy's, the scanner is not optional hygiene - it is the compensating control.

## Sources

- GitHub Docs - Removing sensitive data from a repository: https://docs.github.com/en/enterprise-server@3.21/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
- Gitleaks secret scanning guides (2026): https://dev.to/pickuma/gitleaks-open-source-secret-scanning-for-git-repos-in-2026-4ceb ; https://oneuptime.com/blog/post/2026-01-25-secret-scanning-gitleaks/view
- Pre-commit hook layering practice: https://vibedoctor.io/blog/pre-commit-hooks-secrets-detection
