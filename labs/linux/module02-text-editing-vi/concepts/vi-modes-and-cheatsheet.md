# vi Modes and Command Cheat Sheet - Concepts Reference

This is your full reference for vi. Use it alongside the BUILD guides. Come
back to it any time you need to look something up. The command tables near the
end are made for quick scanning while you work.

---

## 1. Why vi Exists and Why DBAs Must Know It

vi was written in 1976. It has been on almost every Unix and Linux system ever
since. On CentOS Stream 9, the `vi` command actually runs `vim` ("vi
improved"). vim is a modern, backward-compatible version. It adds syntax colors
and undo history.

You will meet vi whether you like it or not:

- It is **always installed**. Nicer editors like `nano`, `emacs`, or GUI tools
  may be missing on a locked-down or minimal server.
- It works over **SSH with no graphics** and on **almost any terminal**.
- It works when the system is **barely alive** - low disk, recovery mode, or
  rescue shells. Heavier tools often refuse to run there.

For a DBA, this is not optional. You edit `postgresql.conf`, `pg_hba.conf`,
`sshd_config`, systemd unit files, and shell scripts all the time. You almost
always do it over SSH. vi is the one editor you can count on being there.

---

## 2. The Modes Model (the core idea)

One idea makes vi click: **modes**. Notepad and VS Code let you type and move
at the same time. vi keeps them separate. There is a mode for moving and giving
commands, and a mode for typing text.

### Command mode (also called normal mode)

- This is where vi **starts** when you open a file.
- Your keystrokes are **commands**, not text. `x` deletes, `dd` deletes a line,
  `/` searches, `:wq` saves and quits.
- Try to type a sentence here and vi reads each letter as a command. It will do
  surprising things. This is the number one beginner shock.

### Insert mode

- This is the "typewriter" mode. Your keystrokes appear as **text**.
- You enter it from command mode with keys like `i`, `a`, `o`, `O`.
- The bottom of the screen shows `-- INSERT --` while you are in it.
- Press **`Esc`** to leave it. That takes you back to command mode.

### Command-line mode (the colon commands)

- Reach it by pressing `:` from command mode. A prompt appears at the bottom.
- Use it for `:w` (write), `:q` (quit), `:wq` (write and quit), `:%s/...`
  (search and replace), and `:64` (jump to line 64).
- These are called "ex commands." vi grew out of an older editor named ex.

### The mode map

```
                press i / a / o / O
   COMMAND  ─────────────────────────►  INSERT
    MODE    ◄─────────────────────────   MODE
                    press Esc

   COMMAND  ── press : ──►  COMMAND-LINE (type command, Enter runs it,
    MODE                    returns to command mode)
```

### The Golden Escape Sequence

Are you lost and not sure what mode you are in? Do this:

1. Press **`Esc`** (this guarantees you are in command mode).
2. Type **`:q!`** and press Enter (this quits and throws away all changes).

Practice it until it is a reflex. Then you can never get stuck in vi.

---

## 3. Entering Insert Mode - The Options

There is more than one way to start typing. Each one puts your cursor in a
different spot. Picking the right one saves you movement.

| Key | Name | Typing starts... |
|-----|------|------------------|
| `i` | insert | Before the cursor |
| `a` | append | After the cursor |
| `I` | insert at start | Before the first non-blank char on the line |
| `A` | append at end | At the very end of the line |
| `o` | open below | On a new blank line below the current one |
| `O` | open above | On a new blank line above the current one |

Notice the pattern. The **capital** key does the "bigger" or line-level version
of the lowercase key. You will see this pattern again and again in vi.

---

## 4. Moving Around

All movement happens in command mode. Learn these keys and you will rarely
reach for the arrow keys.

| Key | Moves cursor to |
|-----|-----------------|
| `h` `j` `k` `l` | Left, down, up, right (one step) |
| `w` / `b` | Start of next word / previous word |
| `e` | End of the current or next word |
| `0` | Start of the current line (column 1) |
| `^` | First non-blank character on the line |
| `$` | End of the current line |
| `gg` | First line of the file |
| `G` | Last line of the file |
| `NG` or `:N` | Line number N (e.g. `64G` or `:64`) |
| `Ctrl+f` / `Ctrl+b` | Forward / back one full screen |
| `Ctrl+d` / `Ctrl+u` | Down / up half a screen |

**Counts:** put a number before most commands to repeat them. `5j` moves down 5
lines. `3w` moves forward 3 words. `10x` deletes 10 characters.

---

## 5. Editing Text

| Key | What it does |
|-----|--------------|
| `x` | Delete the character under the cursor |
| `dd` | Delete (cut) the whole line |
| `dw` | Delete from cursor to start of next word |
| `d$` | Delete from cursor to end of line |
| `dG` | Delete from cursor to end of file |
| `yy` | Yank (copy) the whole line |
| `yw` | Yank a word |
| `p` / `P` | Paste below / above the cursor |
| `u` | Undo the last change |
| `Ctrl+r` | Redo (undo the undo) |
| `r` | Replace the single character under the cursor |
| `cw` | Change a word (delete word, enter insert mode) |
| `cc` | Change the whole line |
| `c$` | Change from cursor to end of line |

### The operator + motion grammar

vi's real power is that **operators** combine with **motions**:

- Operators: `d` (delete), `y` (yank/copy), `c` (change)
- Motions: `w` (word), `$` (end of line), `0` (start of line), `G` (end of
  file), and more

Any operator pairs with any motion: `dw`, `d$`, `dG`, `yw`, `cw`, `c$`. So you
learn a small grammar, not a giant list. Double an operator (`dd`, `yy`, `cc`)
and it acts on the whole line.

---

## 6. Search and Replace

| Command | What it does |
|---------|--------------|
| `/text` | Search forward for `text` |
| `?text` | Search backward for `text` |
| `n` / `N` | Next / previous match (n = same direction as the search) |
| `/text\c` | Case-insensitive search |
| `:%s/old/new/g` | Replace every `old` with `new` in the whole file |
| `:%s/old/new/gc` | Same, but confirm each change (`y`/`n`/`a`/`q`) |
| `:s/old/new/g` | Replace on the current line only |
| `:1,20s/old/new/g` | Replace on lines 1 through 20 |

**Anatomy of `:%s/old/new/g`:** `%` = all lines. `s` = substitute.
`/old/new/` = find and replace. `g` = every match on a line. Without `g`, only
the first match on each line changes.

---

## 7. Saving and Quitting

| Command | What it does |
|---------|--------------|
| `:q` | Quit (only if no unsaved changes) |
| `:q!` | Quit and discard all changes |
| `:w` | Write (save) but keep editing |
| `:wq` | Write and quit |
| `ZZ` | Write and quit (shortcut, no colon) |
| `:wq!` | Force write and quit (overrides a read-only warning you own) |
| `:w filename` | Save a copy to a different filename |

---

## 8. DBA-Relevant Worked Examples

### Jump straight to an error line

PostgreSQL says: `syntax error in file "postgresql.conf" line 64`. Open the
file and type `64G` (or `:64`). No scrolling needed.

### Find a setting and check for duplicates

```
/max_connections
```
Then press `n` again and again. If the setting shows up twice, the last one
wins. A duplicate is a real bug.

### Duplicate and tweak a pg_hba.conf rule

Put the cursor on an existing rule. Press `yy` to copy it. Press `p` to paste a
copy below. Then edit the copy for the new host. This is faster and safer than
retyping the whole rule.

### Add a dated comment above a setting

Put the cursor on the setting. Press `O` to open a line above it. Type
`# changed 2026-07-08 for connection tuning`, then press `Esc`. A config that
documents itself helps the next DBA.

### Bulk change a path safely

```
:%s|/var/lib/pgsql/14|/var/lib/pgsql/16|gc
```
The `c` flag asks before each change. That lets you skip matches inside
comments. (Tip: when the text has slashes in it, you can use `|` as the
separator instead of `/`.)

### Bail out of a bad edit

Press `Esc`, then `:q!`. The file on disk stays untouched. This is why editing
a backup copy, plus `:q!` when things go wrong, makes config work low-risk.

---

## 9. The Config-Editing Discipline

vi is just the tool. The habits you build around it are what keep servers
alive:

1. **Inspect** - look at the file first (`head`, `grep`) so you know what you
   are about to change.
2. **Back up** - run `cp file file.bak-DATE` before you edit anything under
   `/etc`.
3. **Edit** - use `sudo vi file`. Root-owned configs need `sudo`.
4. **Verify** - `grep` the file afterward to confirm your change landed.
5. **Validate** - run the service's own checker (`sshd -t`, or a PostgreSQL
   config reload) before you apply it. Never reload a service on a config you
   have not validated.

---

## 10. Common Beginner Traps and Fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Letters trigger weird actions | You are in command mode | Press `i` to type, or `Esc` then move deliberately |
| `:wq` appears as text in the file | You were in insert mode | Press `Esc` first, then `:wq` |
| Cannot quit, `E37: No write since last change` | Unsaved changes with `:q` | Use `:wq` to save or `:q!` to discard |
| `E45: 'readonly' option is set` | Opened a root file without sudo | `:q!`, then reopen with `sudo vi` |
| Only one line changed on a replace | Forgot the `%` range | Use `:%s/...` to affect all lines |
| Only the first match per line changed | Forgot the `g` flag | Add `g`: `:%s/old/new/g` |
| Totally lost | Unknown mode/state | `Esc` then `:q!` - the golden escape |
