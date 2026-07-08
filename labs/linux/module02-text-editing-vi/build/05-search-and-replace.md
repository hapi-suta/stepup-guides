# Build 05: Search and Replace

You will learn to find text fast and to change it in bulk. A config file can
have hundreds of lines. Searching beats scrolling every time. And when a
setting shows up in many places, search-and-replace changes them all at once.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. Set up a searchable file

Move into your practice folder:

```bash
cd ~/vi-practice
```

Copy a real config with lots of text so search has something to find. The file
is owned by root, so the copy needs `sudo`:

```bash
sudo cp /etc/ssh/sshd_config search-practice.txt
```

`sudo cp` copies a file as root to a new name in your current folder. You work
on the copy, so the real `sshd_config` stays safe.

The copy is still owned by root. Change it to be owned by you so you can open
and edit it as **ec2-user**:

```bash
sudo chown ec2-user:ec2-user search-practice.txt
```

`chown` changes the owner of a file. Now `search-practice.txt` belongs to you.

Open it:

```bash
vi search-practice.txt
```

You are in command mode. Search and replace commands only work in command mode.
If you are ever unsure, press `Esc` first.

---

## 2. Search forward: /pattern

To find text, press `/`, type what you are looking for, and press Enter:

```
/Port
```

- `/` - starts a forward search and shows a `/` prompt at the bottom
- `Port` - the text (pattern) to find
- Enter - jumps to the next occurrence

The cursor jumps to the first `Port` at or after where you are. vim usually
highlights the match too.

```
Expected output (yours will differ):
#Port 22
```

Search cares about capital letters by default. So `/Port` will not match
`port`. To ignore capital letters for one search, add `\c` anywhere in the
pattern, like `/port\c`.

---

## 3. Repeat the search: n and N

After a search, you do not retype it. Just press:

- `n` - jump to the **next** match (same direction as your search)
- `N` - jump to the **previous** match (opposite direction)

Press `n` a few times to step through every `Port` in the file. Then press `N`
to step back. This is how you check every place a setting appears before you
change it.

To search **backward** from the start, use `?` instead of `/`:

```
?Port
```

`?pattern` searches upward toward the top of the file. With `?`, the direction
of `n` and `N` flips: `n` goes up and `N` goes down. That is because `n` always
means "same direction as the original search".

> **DBA Context - Finding a Setting Fast:** A `postgresql.conf` can be 900 lines
> long. Type `/max_connections`, press Enter, and you land on the setting right
> away. Press `n` to see if it appears more than once. Duplicate settings are a
> real bug, because the last one wins. Search is the first tool you reach for
> when you check over a config.

---

## 4. Replace across the whole file: :%s/old/new/g

This is the big one. The substitute command changes text in bulk. Here is the
full form:

```
:%s/old/new/g
```

Break it down piece by piece:

- `:` - open the command line at the bottom
- `%` - apply to **every line** in the file (`%` means "all lines")
- `s` - substitute (search and replace)
- `/old/new/` - find `old`, replace with `new` (the slashes are separators)
- `g` - **g**lobal: replace every match on each line, not just the first

Try replacing every `#Port` comment marker. In this file, run:

```
:%s/#Port/#PORT/g
```

This finds every `#Port` and changes it to `#PORT`. vim tells you how many
changes it made:

```
Expected output (yours will differ):
1 substitution on 1 line
```

Without the `g` at the end, only the **first** match on each line changes. With
`g`, every match on every line changes. For most config edits you want `g`.

> **Concept - The Range Before s:** The `%` in `:%s` is a range. It means "all
> lines". You can pick other ranges too: `:s` (this line only), `:1,10s` (lines
> 1 through 10), and `:.,$s` (from this line to the end). The shape is always
> `:RANGE s/old/new/flags`. If you leave out the range, vi only changes the
> current line. This trips people up a lot: they forget the `%` and wonder why
> only one line changed.

---

## 5. Replace with confirmation: the c flag

Bulk replace is powerful, which also makes it risky. One wrong pattern can wreck
a file. The `c` flag makes vi **ask you** before each change. Add `c` after the
`g`:

```
:%s/HostKey/HOSTKEY/gc
```

- `g` - every match per line
- `c` - **c**onfirm each one

For each match, vim jumps to it and asks:

```
Expected output (yours will differ):
replace with HOSTKEY (y/n/a/q/l/^E/^Y)?
```

Your answer keys:

- `y` - yes, replace this one
- `n` - no, skip this one
- `a` - all, replace this and all remaining without asking
- `q` - quit, stop replacing now
- `l` - last, replace this one then stop

Press `y` or `n` for each match. Confirmation mode is the safe way to do a bulk
edit when you are not sure every match should change.

> **DBA Context - Confirm Before You Wreck a Config:** Say you need to change a
> data directory path. It shows up in several settings, but a couple of matches
> are inside comments you want to leave alone. Run the substitute with `gc`.
> Press `y` on the real settings and `n` on the comments. You get the speed of
> bulk replace and the safety of checking each change. On production configs,
> use `gc` instead of a blind `g`.

---

## 6. If a replace goes wrong: undo

Made a bad substitution? The same `u` from Build 04 works here. Press `Esc` to
make sure you are in command mode, then:

```
u
```

`u` undoes the whole substitute command in one press, even if it changed a
hundred lines. Together with confirmation mode, this gives you a two-layer
safety net: `gc` to check before, `u` to reverse after.

---

## 7. Quit without saving your practice edits

You made changes to a throwaway copy, so throw them away:

```
:q!
```

`:q!` quits and throws away all changes. Your `search-practice.txt` copy stays
as it was. More importantly, the real `/etc/ssh/sshd_config` was never touched,
because you worked on a copy the whole time.

---

## 8. Search and replace quick reference

| Command | What it does |
|---------|--------------|
| `/text` | Search forward for `text` |
| `?text` | Search backward for `text` |
| `n` / `N` | Next / previous match |
| `/text\c` | Case-insensitive search for `text` |
| `:%s/old/new/g` | Replace every `old` with `new` in the whole file |
| `:%s/old/new/gc` | Same, but confirm each change |
| `:s/old/new/g` | Replace on the current line only |
| `:1,20s/old/new/g` | Replace on lines 1 through 20 |
| `u` | Undo the whole substitution |

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Search forward for text with `/pattern`
- [ ] Jump to the next and previous match with `n` and `N`
- [ ] Search backward with `?pattern`
- [ ] Replace all occurrences in a file with `:%s/old/new/g`
- [ ] Explain what the `%` and the `g` do in that command
- [ ] Run a replace with confirmation using the `c` flag and answer `y`/`n`
- [ ] Undo a bad substitution with `u`
- [ ] Explain why you would prefer `gc` over `g` on a production config

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
