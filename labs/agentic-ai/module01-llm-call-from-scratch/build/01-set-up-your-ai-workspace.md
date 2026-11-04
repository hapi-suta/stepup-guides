# Build 01: Set Up Your AI Workspace

**Objective:** Install Python 3.12, create a private Python workspace for this course, install the two pinned AI libraries, and prove your personal SUTA AI key reaches the course LLM proxy.

**Estimated Time:** 20-30 minutes

**Prerequisites:**
- Your **ai-lab** server is running and you can log in as **ec2-user** (ask SutaAI for your login details)
- No Python knowledge needed. Every line is explained.

---

## How this course reaches the AI model

Your server does not talk to Claude directly. It talks to the **SUTA LLM proxy**, and the proxy talks to Claude.

Think of it like PgBouncer in front of PostgreSQL. Your app connects to the pooler, the pooler holds the real connection to the database, and the pooler enforces limits. Here the proxy holds the real (paid) API key, and you get a **personal key** with a **$5 spending cap**. When you hit the cap, the proxy stops your calls. Nobody can run up a surprise bill.

Your personal key is already on your server, in a file called `~/.suta-llm.env`. Prof. Happy's tooling put it there. It never appears in chat or email, and you should never paste it anywhere.

---

## Step 1 - Install Python 3.12

On your **ai-lab** server, as **ec2-user**:

```bash
sudo dnf install -y python3.12
```

`sudo` runs the command as root, because installing software changes the whole system. `dnf` is the package manager on CentOS Stream 9 (like `apt` on Ubuntu). `install` adds a package, `-y` answers "yes" to the confirmation question, and `python3.12` is the package name.

CentOS Stream 9 ships Python 3.9, but the AI libraries we use need Python 3.10 or newer. Version 3.12 installs next to 3.9 and does not replace it, so nothing else on the server breaks.

Expected output (yours will differ):

```text
Installed:
  libnsl2-2.0.0-1.el9.x86_64               mpdecimal-2.5.1-3.el9.x86_64
  python3.12-3.12.15-1.el9.x86_64          python3.12-libs-3.12.15-1.el9.x86_64
  python3.12-pip-wheel-23.2.1-5.el9.noarch

Complete!
```

The word `Complete!` at the end means the install worked.

---

## Step 2 - Confirm the Python version

Still on **ai-lab**, as **ec2-user**:

```bash
python3.12 --version
```

This asks the new Python to print its version. It is the same habit as running `psql --version` after installing PostgreSQL: prove the binary is there before you depend on it.

Expected output (yours will differ):

```text
Python 3.12.15
```

---

## Step 3 - Create the course folder

Still on **ai-lab**, as **ec2-user**:

```bash
mkdir ~/agentic-ai
```

`mkdir` makes a directory. `~` means your home directory (`/home/ec2-user`). Every file you write in this course lives in `~/agentic-ai`.

This command prints nothing when it works.

---

## Step 4 - Move into the course folder

Still on **ai-lab**, as **ec2-user**:

```bash
cd ~/agentic-ai
```

`cd` changes your current directory. From now on, files you create land here.

---

## Step 5 - Create a virtual environment

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python3.12 -m venv .venv
```

A **virtual environment** is a private copy of Python just for this project. `-m venv` runs Python's built-in "make a virtual environment" module, and `.venv` is the folder it creates.

DBA analogy: it is like giving each application its own database instead of dumping every table into `postgres`. Libraries you install for this course cannot clash with anything else on the server.

This command prints nothing when it works.

---

## Step 6 - Activate the workspace on every login

Still on **ai-lab**, as **ec2-user**:

```bash
echo 'source ~/agentic-ai/.venv/bin/activate' >> ~/.bashrc
```

`~/.bashrc` runs every time you log in. `echo '...' >> ~/.bashrc` appends one line to the end of it (two `>` characters mean "add to the end", one `>` would overwrite the whole file, so be careful). The line itself, `source ~/agentic-ai/.venv/bin/activate`, switches your shell to the private Python from Step 5.

Result: every time you log in, `python` and `pip` mean the course's Python 3.12, not the system one.

---

## Step 7 - Load your AI key on every login

Still on **ai-lab**, as **ec2-user**:

```bash
echo 'source ~/.suta-llm.env' >> ~/.bashrc
```

Same idea as Step 6. `~/.suta-llm.env` sets three environment variables: `ANTHROPIC_BASE_URL` (the proxy address), `ANTHROPIC_API_KEY` (your personal key) and `SUTA_LLM_MODEL` (the model the course uses). The Python library reads the first two automatically, so your code never contains a key.

---

## Step 8 - Reload your settings now

Still on **ai-lab**, as **ec2-user**:

```bash
source ~/.bashrc
```

`source` runs a file inside your current shell, so the two lines you just added take effect without logging out and back in.

Your prompt now starts with `(.venv)`. That is the sign your private Python is active.

---

## Step 9 - Confirm which Python you are using

Still on **ai-lab**, as **ec2-user**:

```bash
which python
```

`which` prints the full path of the program a command name points to.

Expected output (yours will differ):

```text
/home/ec2-user/agentic-ai/.venv/bin/python
```

If it prints `/usr/bin/python` instead, Step 8 did not run. Run it again.

---

## Step 10 - Write the pinned library list

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > requirements.txt <<'EOF'
anthropic==2.4.0
openai==3.45.0
EOF
```

This writes a two-line file called `requirements.txt` in one command.

| Part | What it does |
|---|---|
| `cat > requirements.txt` | Send what follows into a new file called `requirements.txt` |
| `<<'EOF'` ... `EOF` | A "here document": every line between them is the file content. The quotes around `'EOF'` mean "copy it exactly, do not change anything" |
| `anthropic==2.4.0` | The official Claude library, pinned to exactly version 2.4.0 |
| `openai==3.45.0` | The official OpenAI library, pinned too. We use it in later modules |

Pinning (`==`) is the same discipline as pinning `postgresql16-server-16.4` in a build: the lab was tested with these exact versions, so a new release next month cannot quietly break it.

---

## Step 11 - Install the libraries

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
pip install -r requirements.txt
```

`pip` is Python's package installer. `-r requirements.txt` means "install everything listed in this file". Because the virtual environment is active, the libraries go into `.venv`, not into the system.

Expected output (yours will differ):

```text
Collecting anthropic==2.4.0 (from -r requirements.txt (line 1))
Collecting openai==3.45.0 (from -r requirements.txt (line 2))
...
Successfully installed annotated-types-0.8.0 anthropic-2.4.0 anyio-4.16.0 ... openai-3.45.0 ... pydantic-2.14.2 ...
```

A notice that a newer `pip` exists is normal. Ignore it.

---

## Step 12 - Prove the library is installed

Still on **ai-lab**, as **ec2-user**:

```bash
pip show anthropic
```

`pip show` prints details about one installed package.

Expected output (yours will differ):

```text
Name: anthropic
Version: 2.4.0
Summary: The official Python library for the anthropic API
...
Location: /home/ec2-user/agentic-ai/.venv/lib64/python3.12/site-packages
...
```

`Version: 2.4.0` and a `Location` inside `agentic-ai/.venv` are the two things that matter.

---

## Step 13 - Check your key file is private

Still on **ai-lab**, as **ec2-user**:

```bash
ls -l ~/.suta-llm.env
```

`ls -l` lists a file with its permissions.

Expected output (yours will differ):

```text
-rw-------. 1 ec2-user ec2-user 311 Nov  4 05:31 /home/ec2-user/.suta-llm.env
```

`-rw-------` means only you (ec2-user) can read it, exactly like a `.pgpass` file that PostgreSQL refuses to use unless it is mode 600. Do not `cat` this file into a chat or a screenshot: it holds your key.

If the file is missing, tell SutaAI. Prof. Happy has to issue your key first.

---

## Step 14 - Ask the proxy about your key

Still on **ai-lab**, as **ec2-user**:

```bash
curl -s -H "Authorization: Bearer $ANTHROPIC_API_KEY" $ANTHROPIC_BASE_URL/key/info | python -m json.tool | grep -E '"(key_alias|spend|max_budget)"'
```

This is your first network call to the proxy. It does not use the AI model, so it costs nothing.

| Part | What it does |
|---|---|
| `curl -s` | Make a web request, silently (no progress bar) |
| `-H "Authorization: Bearer $ANTHROPIC_API_KEY"` | Send your key in a header. `$ANTHROPIC_API_KEY` is filled in from the environment, so the key is never typed on screen |
| `$ANTHROPIC_BASE_URL/key/info` | The proxy page that describes the key you sent |
| `python -m json.tool` | Pretty-print the JSON reply, one field per line |
| `grep -E '"(key_alias\|spend\|max_budget)"'` | Keep only three lines: your key's name, how much you have spent, and your cap |

Expected output (yours will differ):

```text
        "key_alias": "suta-ZZ900",
        "spend": 0.0,
        "max_budget": 5.0,
```

`key_alias` shows your student ID, `spend` is dollars used so far, and `max_budget` is your cap. Your workspace is ready.
