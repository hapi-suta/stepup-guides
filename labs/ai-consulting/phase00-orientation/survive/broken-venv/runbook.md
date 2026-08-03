# SURVIVE Runbook: Broken Virtual Environment

**Phase 0 - SURVIVE scenario 1 of 3**

## The situation

You sit down to work on your project. You activate the virtual environment and try to run your code, but Python cannot find the `requests` package - even though you are sure you installed it. Something is wrong with your environment.

This is one of the most common beginner problems: packages get installed into the **system Python** instead of the **virtual environment**, or the venv's interpreter is broken. This runbook teaches you to diagnose and fix it.

Every command block tells you **which server** and **which user** you are. You do all of this on your **lab server** as **ec2-user**.

---

## Step 1: Reproduce the problem

First, break the environment so you can practice fixing it.

On your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/phase00-orientation/survive/broken-venv/inject.sh
```

(If your copy of the scenario is elsewhere, adjust the path to where `inject.sh` lives.)

This creates a project folder `~/survive-venv-lab` with a broken venv.

---

## Step 2: Move into the project

On your **lab server**, as **ec2-user**:

```bash
cd ~/survive-venv-lab
```

`cd` changes directory.

---

## Step 3: Try to activate the venv and see it fail

Attempt to use the environment the normal way.

Still on your **lab server**, as **ec2-user**:

```bash
source venv/bin/activate
```

`source` runs the activate script in your current shell. Your prompt may now show `(venv)`.

Now ask which Python you are using:

```bash
which python
```

`which` shows the full path of the command that would run.

Expected output (yours will differ):

```
~/survive-venv-lab/venv/bin/python
```

That path looks right, but the file it points to is broken. Prove it:

```bash
python --version
```

Expected output (this is the symptom):

```
bash: .../venv/bin/python: /usr/bin/definitely-not-python: bad interpreter: No such file or directory
```

That error means the venv's `python` is a symlink to an interpreter that does not exist. The venv is broken.

---

## Step 4: Confirm the package went to the wrong place

Leave the broken venv:

```bash
deactivate
```

`deactivate` exits the virtual environment. The `(venv)` prefix disappears. (If `deactivate` errors because the venv never fully activated, just continue.)

Now check where `requests` actually is, using the system Python:

```bash
python3 -c "import requests; print(requests.__file__)"
```

`python3 -c` runs a short Python snippet. This imports `requests` and prints the file it loaded.

Expected output (yours will differ):

```
/home/ec2-user/.local/lib/python3.9/site-packages/requests/__init__.py
```

Note the `.local` path - that is the **system user** site, NOT your venv. That is the root cause: the package was installed globally, so it is invisible inside a clean venv. Your project must not depend on globally installed packages, because another machine will not have them.

---

## Step 5: Check your environment variables

A quick way to see if a venv is really active is the `VIRTUAL_ENV` variable.

Still on your **lab server**, as **ec2-user**:

```bash
echo $VIRTUAL_ENV
```

`echo` prints a value. `$VIRTUAL_ENV` is set only when a venv is active.

Expected output when NO venv is active (empty line):

```

```

If this is empty, no venv is active - a common reason `pip install` lands in the system Python.

---

## Step 6: Delete the broken venv

The clean fix is to rebuild the venv from scratch.

Still on your **lab server**, as **ec2-user**, inside `~/survive-venv-lab`:

```bash
rm -rf venv
```

`rm -rf venv` removes the venv folder and everything in it. `-r` is recursive, `-f` forces without prompting. This is safe here because a venv is disposable - you recreate it from your package list.

---

## Step 7: Create a fresh virtual environment

Pick your project Python. Use 3.12 if you have it.

Still on your **lab server**, as **ec2-user**:

```bash
python3.12 -m venv venv
```

`python3.12 -m venv venv` builds a new isolated environment in a folder called `venv`. (If `python3.12` is not installed, use `python3` instead.)

---

## Step 8: Activate the fresh venv and confirm it

Activate it:

```bash
source venv/bin/activate
```

Your prompt shows `(venv)`. Confirm the interpreter now works:

```bash
python --version
```

Expected output (yours will differ):

```
Python 3.12.13
```

Confirm you are pointed inside the venv:

```bash
echo $VIRTUAL_ENV
```

Expected output (yours will differ):

```
/home/ec2-user/survive-venv-lab/venv
```

`$VIRTUAL_ENV` is now set - the venv is truly active.

---

## Step 9: Install the package INSIDE the venv

With the venv active, install `requests`. Because the venv is active, it lands in the right place.

Still on your **lab server**, as **ec2-user**, with `(venv)` showing:

```bash
pip install requests
```

`pip` here is the venv's pip, so the package installs into the venv.

Confirm it loads from the venv, not the system:

```bash
python -c "import requests; print(requests.__file__)"
```

Expected output (yours will differ - note the path is inside your venv):

```
/home/ec2-user/survive-venv-lab/venv/lib/python3.12/site-packages/requests/__init__.py
```

The path now contains `venv` - the package is correctly isolated.

---

## Step 10: Validate

Run the validator to confirm the fix.

Still on your **lab server**, as **ec2-user**, with the venv active:

```bash
bash ~/aiconsult-staging/phase00-orientation/survive/broken-venv/validate.sh
```

Expected output when fixed:

```
[validate] PASS: venv is active and 'requests' loads from inside the venv
```

If it fails, re-read the message it prints and repeat the step it points to.

---

## What you learned

- A virtual environment isolates a project's packages. `which python` and `echo $VIRTUAL_ENV` tell you if it is really active.
- Installing packages while NO venv is active pollutes the system Python and breaks reproducibility.
- A venv is disposable: when it breaks, delete it and rebuild, then reinstall packages inside it.
- Always activate the venv **before** you `pip install`.
