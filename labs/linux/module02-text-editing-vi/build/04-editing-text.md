# Build 04: Editing Text

You will learn the core editing commands: delete, copy, paste, replace, and the
all-important undo. These are the commands you use to actually change a config
file. Undo is your safety net, so you can experiment without fear.

**Time estimate:** 50 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. Set up a practice file

Move into your practice folder:

```bash
cd ~/vi-practice
```

Create a small file to edit. We will type a few lines into it using vi itself.
That gives you more practice switching between modes.

```bash
vi edit-practice.txt
```

Press `i` to enter insert mode, then type these lines exactly (press Enter
after each):

```
listen_addresses = localhost
max_connections = 100
shared_buffers = 128MB
work_mem = 4MB
this line is a mistake
```

Press `Esc` to return to command mode. Save but stay open with `:w`:

```
:w
```

`:w` saves the file to disk without quitting, so you keep editing. You should
see a confirmation at the bottom like `"edit-practice.txt" 5L, ... written`.

Everything below runs in command mode. If letters start appearing in your text,
press `Esc`.

---

## 2. Delete a single character: x

Move the cursor onto any character and press:

```
x
```

`x` deletes the single character under the cursor. It works like a
forward-delete key. The text to the right shifts left to fill the gap. Press `x`
a few times and watch characters vanish one by one.

A count works: `5x` deletes five characters starting at the cursor.

---

## 3. Delete a whole line: dd

Move to the line `this line is a mistake` (remember `G` jumps to the last
line). Press `d` twice:

```
dd
```

`dd` deletes the whole line the cursor is on and closes the gap. The `d` means
"delete". Doubling it to `dd` means "delete the whole line".

A count works: `2dd` deletes two lines starting at the cursor. When you delete
in vi, the text is not thrown away. It gets copied to a clipboard, which vi
calls a "register". So you can paste it back later. That is why the next section
on paste matters.

---

## 4. Delete a word: dw

Move the cursor to the start of a word and press:

```
dw
```

`dw` means "delete from the cursor to the start of the next word". It combines
the `d` command (delete) with the `w` movement (word) from Build 03. Combining a
command with a movement is the deep pattern behind all of vi.

Some useful cousins:

- `d$` - delete from the cursor to the end of the line (`d` + the `$` movement)
- `d0` - delete from the cursor back to the start of the line

> **Concept - Operator + Motion:** vi's real power is that commands like `d`
> (delete), `y` (yank/copy), and `c` (change) combine with any movement.
> `dw` deletes a word. `d$` deletes to the end of the line. `dG` deletes to the
> end of the file. Learn one command and one movement, and you get their
> combination for free. You are not memorizing hundreds of commands. You are
> learning a small grammar.

---

## 5. Copy and paste: yy and p

In vi, copying is called "yanking". Move to the `shared_buffers` line and press
`y` twice:

```
yy
```

`yy` yanks (copies) the whole current line into the register. Nothing looks
different on screen. The copy stays hidden until you paste it.

Now move to a different line and press:

```
p
```

`p` pastes the yanked line **below** the current line. Capital `P` pastes
**above** it. You should see a copy of the `shared_buffers` line appear.

Paste also works after a delete, because delete copies too. Try this. Press `dd`
to delete a line. Move somewhere else. Press `p`, and the deleted line reappears
there. That is how you "move" a line in vi: `dd` to cut it, move, then `p` to
paste.

Counts work with paste: after yanking a line, `3p` pastes three copies.

> **DBA Context - Duplicating a Config Line:** A common task is copying a
> `pg_hba.conf` rule and tweaking the copy for a new host. Put the cursor on the
> rule. Press `yy` to copy it. Press `p` to paste a copy below. Then edit the
> copy. This is far faster and safer than retyping the whole line.

---

## 6. Undo and redo: u and Ctrl+r

This is the command that makes vi safe to experiment in. In command mode, press:

```
u
```

`u` undoes your last change. Press it again to undo the change before that. Keep
pressing to go back further. vim remembers a long history, so you can walk back
through many edits.

To redo (undo an undo), hold `Ctrl` and press `r`:

```
Ctrl+r
```

`Ctrl+r` puts back a change you just undid. With `u` and `Ctrl+r`, you can move
back and forth through your edit history as much as you want.

Try it. Delete a line with `dd`. Press `u` to bring it back. Press `Ctrl+r` to
delete it again. Nothing is ever truly lost until you save and quit.

> **Concept - Undo Is Your Net:** `u` undoes changes one step at a time. So you
> can try an edit, decide you do not like it, and back it out right away. This
> is why vi is safe for beginners on real configs. As long as you have not
> saved, `u` walks you back. Even after saving, undo still works as long as you
> have not quit. And when you are really in doubt, `:q!` throws away everything
> since the last save.

---

## 7. Replace one character: r

Sometimes you just need to swap one character. Say you want to change a `9` to
an `8` in a port number. Move onto the character. Then press `r` followed by the
new character:

```
r
```

Then press, for example, `8`. `r` means "replace one character". It does not put
you into insert mode. You press `r`, then one replacement character, and you are
done. You stay in command mode. This is perfect for one-character fixes without
the full insert steps.

Try it on the `max_connections = 100` line. Move onto the first `0` and press
`r` then `2`. The line becomes `max_connections = 120`. Adjust it as you like.

---

## 8. Change a word: cw

The `c` command means "change". It deletes something and drops you straight into
insert mode, so you can type the replacement. The most common one is `cw`:

```
cw
```

`cw` deletes from the cursor to the end of the word and immediately enters
insert mode. Type the new word, then press `Esc`.

Try it. Move to the start of `localhost` on the `listen_addresses` line. Press
`cw`, type `*`, then press `Esc`. The line now reads `listen_addresses = *`.

Cousins of `cw`:

- `cc` - change the whole line (clears the line, enters insert mode)
- `c$` - change from the cursor to the end of the line

Notice the pattern again. It is `c` plus a movement, just like `d` plus a
movement. `cw`, `c$`, and `cc` mirror `dw`, `d$`, and `dd`. The only difference
is that `c` leaves you in insert mode, ready to type.

---

## 9. Save your work and review

Save and quit:

```
:wq
```

Look at the result:

```bash
cat edit-practice.txt
```

`cat` prints the file. Your exact output depends on which edits you kept. It
should look roughly like this:

```
Expected output (yours will differ):
listen_addresses = *
max_connections = 120
shared_buffers = 128MB
shared_buffers = 128MB
work_mem = 4MB
```

The `this line is a mistake` line is gone, since you deleted it with `dd`. You
may also see a repeated `shared_buffers` line from your paste practice. The
exact content will vary. What matters is that the commands worked.

---

## 10. Editing quick reference

| Key | What it does |
|-----|--------------|
| `x` | Delete the character under the cursor |
| `dd` | Delete the whole line (and copy it) |
| `dw` | Delete from cursor to start of next word |
| `d$` | Delete from cursor to end of line |
| `yy` | Yank (copy) the whole line |
| `p` / `P` | Paste below / above the cursor |
| `u` | Undo the last change |
| `Ctrl+r` | Redo (undo the undo) |
| `r` | Replace the single character under the cursor |
| `cw` | Change a word (delete word, enter insert mode) |
| `cc` | Change the whole line |

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Delete a single character with `x`
- [ ] Delete a whole line with `dd`
- [ ] Delete a word with `dw`
- [ ] Copy a line with `yy` and paste it with `p`
- [ ] Move a line by cutting with `dd` and pasting with `p`
- [ ] Undo a change with `u` and redo it with `Ctrl+r`
- [ ] Replace a single character with `r`
- [ ] Change a word with `cw`
- [ ] Explain the operator + motion pattern (e.g. why `dw` and `cw` are related)

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
