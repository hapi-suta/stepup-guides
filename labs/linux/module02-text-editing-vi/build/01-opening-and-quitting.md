# Build 01: Opening and Quitting vi

You will learn how to open a file in vi. Most important, you will learn how to
get back out again. vi traps more beginners than any other Linux tool. Almost
always the problem is "I cannot quit". We fix that first, so you never feel
stuck.

**Time estimate:** 40 minutes

All steps run on your lab server. Connect with SSH first.

---

## Step 0 - Why vi?

vi (say "vee-eye") is a text editor. It lives on every Linux and Unix server
ever made. It is always installed. It works over SSH with no graphics. It even
works on a broken server when nothing else does. It works when the disk is
almost full and other tools give up.

On CentOS Stream 9, the command `vi` actually runs `vim` ("vi improved"). vim
is a newer version with colors and extra features. Everything in this module
works in both. We will type `vi` throughout.

> **DBA Context - Why This Matters:** DBAs edit config files all day long, such
> as `postgresql.conf`, `pg_hba.conf`, `sshd_config`, and systemd unit files.
> You will almost always do this over SSH on a server with no desktop. vi is
> the one tool that is always there. Learn it once, and you can edit a file on
> any server, anywhere - even during a 3 a.m. outage.

---

## Step 1 - The one idea that makes vi make sense: modes

Most editors you have used (Notepad, TextEdit, VS Code) have one mode. You type
and letters appear. vi is different. vi has separate modes. This is the one
thing that confuses every beginner.

There are two modes you must know right now:

- **Command mode** - your keys are commands, not text. Pressing `x` deletes a
  character. Pressing `dd` deletes a line. This is where vi starts.
- **Insert mode** - your keys are typed as text, like a normal editor.

When you open a file, vi starts in **command mode**. If you start typing
sentences right away, strange things happen. vi is reading your letters as
commands. This surprises almost every beginner.

Here is the rule that stops the panic: **when in doubt, press `Esc`**. `Esc`
always takes you back to command mode. From command mode, you can always quit
safely. We will lean on this for the whole module.

---

## Step 2 - Open a file

First, make a practice folder and move into it:

```bash
mkdir -p ~/vi-practice
```

`mkdir` makes a directory. The `-p` flag means "create parent directories if
needed and do not error if it already exists".

```bash
cd ~/vi-practice
```

`cd` changes your current directory to the practice folder.

Now open a new file in vi:

```bash
vi notes.txt
```

`vi` is the editor command. `notes.txt` is the file to open. If the file does
not exist yet, vi opens an empty screen. It will create the file when you save.

You should now see a mostly empty screen with tilde `~` characters down the
left side:

```
Expected output (yours will differ):
~
~
~
~
"notes.txt" [New]
```

The `~` lines mean "this line is past the end of the file". They are not part
of your file. The bottom line is a status line. `[New]` means this is a
brand-new file. Right now you are in command mode.

---

## Step 3 - Quit without saving (the escape hatch)

Before you type anything, learn how to leave. This is the command that stops
the panic.

Type a colon `:`. Watch the bottom-left corner. A `:` appears there. This is
the "command line", where you type longer commands. Now type `q` and press
Enter:

```
:q
```

- `:` - switches to the command-line at the bottom of the screen
- `q` - means "quit"
- Enter - runs it

If the file has no unsaved changes, vi closes and you land back at your shell
prompt:

```
Expected output (yours will differ):
[ec2-user@ip-10-0-1-50 vi-practice]$
```

If `:q` refuses and shows an error like `E37: No write since last change`, it
means you have unsaved changes. The next step handles that.

> **Concept - The Colon Commands:** Commands that start with `:` are called
> "ex commands". (vi grew out of an older editor called ex.) They always run
> from command mode. They appear at the bottom of the screen. They need Enter
> to run. `:q`, `:w`, and `:wq` are the three you will use all the time.

---

## Step 4 - Make a change, then force quit

Open the file again:

```bash
vi notes.txt
```

Now press the letter `i` once. This enters **insert mode**. (The next guide
covers this in depth.) Look at the bottom of the screen. It should say:

```
Expected output (yours will differ):
-- INSERT --
```

Type a line of text, for example:

```
this is a throwaway line
```

Now press `Esc` to return to command mode. The `-- INSERT --` marker
disappears.

You have unsaved changes. To quit and **throw them away**, use `:q!`:

```
:q!
```

- `:q` - quit
- `!` - force it, discarding unsaved changes

The `!` means "I really mean it, do not warn me". vi closes and your typed line
is gone. This is your safety hatch. If you ever mess up a config file and want
to bail out without saving the damage, `:q!` gets you out clean.

> **DBA Context - When to Use :q!:** Say you open `postgresql.conf`, start
> editing, and realize you are in the wrong file or made a mess. `:q!` leaves
> the file exactly as it was on disk. Nothing you typed is saved. This is much
> safer than trying to undo every change by hand. On production configs, when
> in doubt, bail with `:q!` and start over.

---

## Step 5 - Save and quit (the normal way)

Open the file one more time:

```bash
vi notes.txt
```

Press `i` for insert mode, type:

```
this line I want to keep
```

Press `Esc` to go back to command mode. Now save and quit with `:wq`:

```
:wq
```

- `:w` - write (save) the file to disk
- `q` - quit
- together, `:wq` means "save, then quit"

vi writes the file and closes. The status line briefly confirms the write:

```
Expected output (yours will differ):
"notes.txt" 1L, 25B written
```

`1L` means one line was written. `25B` means 25 bytes. Now confirm the file
really exists on disk. Read it with `cat`:

```bash
cat notes.txt
```

`cat` prints a file's contents to the screen.

```
Expected output (yours will differ):
this line I want to keep
```

Your text survived. That is the full round trip: open, edit, save, quit, and
verify.

---

## Step 6 - The shortcuts: ZZ and :w

There are faster ways to do the same things. You do not need to memorize them
now. You will see them in other guides.

- `ZZ` (two capital Z's, in command mode, no colon) - saves and quits, just
  like `:wq`. Hold Shift and press `Z` twice.
- `:w` (with Enter) - saves the file but stays open, so you can keep editing.
- `:wq!` - forces a save and quit. Useful when a file is marked read-only but
  you own it.

Try `ZZ`. Open the file:

```bash
vi notes.txt
```

Press `i`, add another line, press `Esc`, then type two capital Z's:

```
ZZ
```

vi saves and quits with no colon needed. Verify again:

```bash
cat notes.txt
```

```
Expected output (yours will differ):
this line I want to keep
a second line added with ZZ
```

---

## Step 7 - The quit cheat sheet

Keep this table where you can see it. Every one of these runs from command
mode. (Press `Esc` first if you are not sure which mode you are in.)

| I want to... | Type this | What it does |
|--------------|-----------|--------------|
| Quit, no changes made | `:q` | Quits only if nothing changed |
| Quit and throw away changes | `:q!` | Discards everything since last save |
| Save and quit | `:wq` | Writes to disk, then quits |
| Save and quit (shortcut) | `ZZ` | Same as `:wq`, no colon |
| Save but keep editing | `:w` | Writes to disk, stays open |
| Force save and quit | `:wq!` | Overrides a read-only warning you own |

> **Concept - The Golden Escape Sequence:** Are you ever lost in vi, not sure
> what mode you are in or what you typed? Do this every time. Press `Esc`, then
> type `:q!` and Enter. This throws away any changes and gets you out, no
> matter what state vi is in. Practice it until it is muscle memory. Then you
> will never be trapped in vi again.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain in one sentence why vi has modes
- [ ] Open a file with `vi filename`
- [ ] Recognize command mode versus insert mode (the `-- INSERT --` marker)
- [ ] Quit a file with no changes using `:q`
- [ ] Quit and discard changes using `:q!`
- [ ] Save and quit using `:wq`
- [ ] Save and quit using the `ZZ` shortcut
- [ ] Perform the golden escape sequence `Esc` then `:q!` from memory
- [ ] Verify your saved text with `cat`

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
