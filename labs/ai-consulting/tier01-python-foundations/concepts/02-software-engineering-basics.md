# Concepts: Software Engineering Basics

**Read this before you touch the keyboard.** Writing code that runs once on your laptop is easy. Shipping code that a team can change, review, test, and deploy without breaking is the actual job. This is the vocabulary of that job. As a DBA you already run change control and backups - this is the same discipline applied to application code.

Everything here maps to how Project 1 is structured: pinned `requirements.txt`, secrets from environment variables, tests that run in CI, errors that are logged not swallowed.

---

## 1. Requirements: know what you are building first

A **requirement** is a plain statement of what the software must do. Before writing code, write down the behavior in one or two sentences.

- **Functional requirement** - what it does: "Return a count of support tickets per category."
- **Non-functional requirement** - how well it does it: "Respond in under 500ms; return 503 if the database is down."

Vague requirements produce wrong software fast. "Summarize tickets" is not a requirement. "Group tickets by category and return totals as JSON, treating blank subjects as skipped and empty categories via keyword rules" is. Project 1's `/summary` endpoint is exactly the second version made real.

---

## 2. Source control (Git)

**Git** is the system that tracks every change to your code, who made it, and when - and lets you undo any of it. It is the single most important tool in software engineering. You do not email `app_final_v2_REAL.py` around; you commit.

Core mental model:

- **Repository (repo)** - the project folder Git is tracking.
- **Commit** - a saved snapshot of your changes with a message. Small, focused commits are gold.
- **Staging** - you pick which changes go into the next commit (`git add`).
- **History** - the ordered list of commits; you can view, compare, and revert any of them.

```bash
git status                 # what changed
git add app.py             # stage a file for the next commit
git commit -m "feat: add /summary endpoint"   # save a snapshot
git log --oneline          # see history
```

**Commit messages matter.** Use a convention like `feat:` (new feature), `fix:` (bug fix), `docs:`, `refactor:`, `test:`, `chore:`. This is the Conventional Commits spec (see: conventionalcommits.org), and a `feat:`/`fix:` prefix can drive automated version bumps. A future you reading `git log` should understand what happened without opening the diff.

---

## 3. Branching

A **branch** is an independent line of work. `main` is the stable, always-working branch. You never commit half-finished work directly to `main`; you branch off, do the work, and merge back when it is done and reviewed.

```bash
git switch -c feature/pagination    # create and switch to a new branch
# ... make changes, commit ...
git switch main                     # go back to main
git merge feature/pagination        # bring the work in
```

Naming: `feature/description`, `fix/description`, `docs/description`. Branches let five people work at once without stepping on each other, and let you throw away a bad idea by deleting the branch - `main` never saw it.

---

## 4. Pull requests (PRs)

A **pull request** is a proposal to merge one branch into another, opened on a platform like GitHub. It is where the change is discussed and reviewed before it lands. A PR shows the **diff** (exactly what lines changed), runs the automated tests, and collects reviewer comments.

Flow: branch -> commit -> push -> open PR -> tests run + reviewer reads it -> address comments -> merge. The PR is the gate. Nothing reaches `main` without passing through it. This is your application-code equivalent of a database change-approval ticket.

---

## 5. Code reviews

A **code review** is another engineer reading your change before it merges. It is not an insult - it is how bugs get caught cheaply and how the team keeps a shared understanding of the code.

What a good review looks for:

- Correctness - does it actually do the requirement?
- Errors handled, not swallowed (see [01-python-fundamentals.md](01-python-fundamentals.md) section 8).
- No secrets hardcoded.
- Tests included for new behavior.
- Readable names and small functions.

As the author: keep PRs small, explain the "why" in the description, and respond to every comment. As the reviewer: be specific and kind, and approve when it is good enough, not perfect.

---

## 6. Testing (as a practice)

You saw unit tests in the Python concepts. As an engineering practice, the levels are:

- **Unit tests** - one function in isolation, no database or network. Fast. `test_categorize`.
- **Integration tests** - several pieces together, e.g. the API talking to a real database.
- **End-to-end (E2E)** - the whole system as a user would hit it.

The **testing pyramid**: many fast unit tests at the bottom, fewer integration tests, very few slow E2E tests at the top. Write tests for new behavior before you call it done. A change with no test is a change nobody can safely touch later.

---

## 7. Debugging

Debugging is finding out **why** code does the wrong thing - methodically, not by guessing.

The method:

1. **Reproduce** it reliably. If you cannot make it fail on command, you cannot know you fixed it.
2. **Read the error** - the traceback names the file, line, and exception type. Read it bottom-up: the last line is the actual error.
3. **Narrow it down** - add logging or use `print`/a debugger to see the values at the point of failure.
4. **Form one hypothesis, test it, repeat.** Change one thing at a time.
5. **Fix, then add a test** that would have caught it, so it never comes back.

The SURVIVE scenarios in this tier are structured debugging drills - something breaks, you diagnose, you recover.

---

## 8. Dependency management

**Dependencies** are the third-party packages your code needs. Managing them means: knowing exactly which ones and which versions, and installing them reproducibly.

- **`requirements.txt`** lists them with pinned versions: `fastapi==0.115.0`. Pinning = everyone installs the identical version, so behavior is identical everywhere.
- **Virtual environment (`venv`)** - an isolated per-project Python with its own installed packages, so Project A's `fastapi==0.115` does not clash with Project B's `fastapi==0.99`. You created one in BUILD Step 3: `python3.12 -m venv .venv` then `source .venv/bin/activate`.
- Install everything with `pip install -r requirements.txt`.

Never `pip install` into the system Python. Always activate a venv first. When you add a package, add it to `requirements.txt` with a pinned version in the same commit.

---

## 9. Configuration management

**Configuration** is everything that changes between environments (dev, staging, production) without changing the code: database host, port, log level, feature flags. The principle (from the Twelve-Factor App methodology, factor III - "store config in the environment"; see: 12factor.net): **config lives outside the code**.

Hardcoding `DB_HOST = "prod-db.internal"` in `app.py` means you must edit and redeploy code to point at a different database. Reading it from the environment means the same image runs anywhere - you just change the environment. That is why `app.py` does `DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")`: environment first, safe local default second.

---

## 10. Environment variables

An **environment variable** is a named value the operating system hands to your process. It is the standard channel for configuration and secrets.

```bash
export DB_HOST=127.0.0.1        # set one for this shell
export DB_PASSWORD=labpass
python app.py                   # the process reads them via os.environ
```

```python
import os
db_host = os.environ.get("DB_HOST", "127.0.0.1")  # value or a default
```

In Docker you pass them with `-e`: `docker run -e DB_PASSWORD=labpass ...` (BUILD Step 6). They are not baked into the image, so the same image is safe to share.

---

## 11. Secrets

A **secret** is any credential: database passwords, API keys, tokens, private keys. The rules are absolute:

- **Never hardcode a secret in source code.** Source ends up in Git history forever - a hardcoded secret is a permanent leak even after you "delete" it.
- **Never commit a secret.** Keep secret values in environment variables or a secrets manager (AWS Secrets Manager, Vault). Commit a `.env.example` with blank values as documentation, and add real `.env` files to `.gitignore`.
- **Rotate on leak.** If a secret is exposed, assume it is compromised: rotate (issue a new one, revoke the old) before anything else. Scrubbing it from Git alone is not enough - it was public.

You will inject, rotate, and scrub a leaked secret in the `committed-secret` SURVIVE scenario. This is the single most common security failure in real codebases.

---

## 12. Application logging (in production)

Beyond the Python `logging` mechanics, the engineering practice is:

- Log at the right level: `INFO` for normal events, `WARNING` for recoverable oddities (a skipped bad row), `ERROR` for failures.
- Include context: which ticket, which endpoint, which user - so a log line is actionable on its own.
- **Structured logs** (key=value or JSON) are searchable at scale. `log.info("summary total=%d skipped=%d", total, skipped)` beats a vague sentence.
- Never log secrets or full personal data.
- Logs are how you debug production, where you cannot attach a debugger. Treat them as a first-class feature, not an afterthought.

---

## 13. Basic API design

An **API** (Application Programming Interface) is a contract for how other programs talk to yours. Full detail is in [04-apis.md](04-apis.md); the design principles you apply now:

- **Predictable endpoints**: a noun and a verb via HTTP method. `GET /summary` reads; you would `POST /tickets` to create.
- **Clear responses**: return JSON with a stable shape. `/summary` always returns `{"total": ..., "by_category": {...}}`.
- **Honest status codes**: `200` success, `4xx` the caller's fault, `5xx` your fault. `app.py` returns `503` when the database is down - honest, not a fake `200`.
- **A health check**: `GET /health` so load balancers and monitors can tell if you are alive. You built this.
- **Do not break the contract**: once other code depends on your shape, changing it silently breaks them. Version the API if you must change it.

---

## 14. Documentation

Documentation is how the next person (often future you) uses and changes the code without reverse-engineering it.

- **README** - what the project is, how to run it, how to test it. The first file anyone opens.
- **Docstrings** - the `"""..."""` at the top of a function or module explaining what it does. `app.py`'s functions all have them.
- **Inline comments** - explain **why**, not what. `# skip records with no subject` tells you the intent; the code already tells you the mechanics.
- **The API contract** - FastAPI auto-generates interactive docs at `/docs` from your code and type hints, which is a large reason it is used for AI services.

Good docs are concise and current. Stale docs are worse than none, because they lie.

---

## Vocabulary recap

- **requirement** - a clear statement of what the software must do.
- **Git / repo / commit / staging / history** - version control and its pieces.
- **branch** - an independent line of work; `main` stays stable.
- **pull request (PR) / diff** - the reviewed proposal to merge.
- **code review** - a peer reading your change before it lands.
- **unit / integration / E2E test; testing pyramid** - levels of automated testing.
- **debugging** - methodically finding why code misbehaves: reproduce, read, narrow, fix, test.
- **dependency / requirements.txt / venv / pinning** - reproducible third-party packages.
- **configuration / config-out-of-code** - environment-specific settings live outside the code.
- **environment variable** - OS-provided named value for config and secrets.
- **secret / never hardcode / rotate** - credentials and how to handle a leak.
- **application logging / structured logs** - leveled, contextual, searchable output.
- **API design / status codes / health check / contract** - designing a program-to-program interface.
- **documentation / README / docstring** - how the next person uses your code.

Next: [03-sql-for-ai-and-analytics.md](03-sql-for-ai-and-analytics.md) - the SQL that prepares data for models and analytics.

---

## References

- Git reference documentation: https://git-scm.com/docs
- Conventional Commits specification: https://www.conventionalcommits.org/
- The Twelve-Factor App, Factor III - Config (store config in the environment): https://12factor.net/config
- Python venv documentation: https://docs.python.org/3/library/venv.html
- pip user guide (requirements files, pinning): https://pip.pypa.io/en/stable/user_guide/
- Python Logging HOWTO: https://docs.python.org/3/howto/logging.html
- FastAPI documentation (auto-generated `/docs`): https://fastapi.tiangolo.com/
