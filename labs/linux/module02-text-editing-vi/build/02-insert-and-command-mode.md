# Build 02: Command Mode and Insert Mode

You will build the idea that makes vi click: two modes, and how to move between
them. Once this clicks, the rest of vi is just learning single commands.

**Time estimate:** 40 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. The two-mode mental model

Think of vi like a car with two gears:

- **Command mode** is the "controls" gear. Keys steer, delete, copy, paste,
  and search. You do not type sentences here. vi always starts in this gear.
- **Insert mode** is the "typewriter" gear. Keys make letters on screen, like
  any normal editor.

You cannot type text in command mode. You cannot run commands in insert mode.
The whole skill of vi is knowing which gear you are in. Then you switch between
them on purpose.

Two facts to burn into memory:

1. You **enter** insert mode from command mode by pressing a key like `i`.
2. You **leave** insert mode back to command mode by pressing `Esc`.

The bottom of the screen tells you where you are. In insert mode it shows
`-- INSERT --`. In command mode it shows nothing, or your last command.

> **Concept - Why Two Modes?** vi was built in 1976 for slow terminals. Back
> then there was no mouse, and no arrow keys you could trust. Making every
> letter key a possible command lets you edit fast, with your hands never
> leaving the home row. It feels strange for an hour, then it feels fast
> forever. Many server tools borrow vi's keys, such as `less`, `man`, and
> `psql`'s pager. So learning them pays off far beyond the editor.

---

## 2. Set up a practice file

Move into your practice folder:

```bash
cd ~/vi-practice
```

`cd` changes into the folder you made in the previous guide.

Open a fresh file:

```bash
vi modes.txt
```

`vi` opens the editor; `modes.txt` is a new file. You start in command mode.

---

## 3. The ways to enter insert mode

There is not just one key to start typing. vi gives you several. Each one
starts typing in a different place. This is handy. You pick the one that puts
your cursor exactly where you want it.

Press each key below, one at a time. Watch what happens. Then press `Esc` to go
back to command mode before you try the next one.

### i - insert before the cursor

```
i
```

Press `i`. The bottom shows `-- INSERT --`. Anything you type appears to the
left of where the cursor was. Type:

```
hello world
```

Press `Esc`. You are back in command mode.

`i` = "insert here". It is the one you will use most.

### a - append after the cursor

Move the cursor onto a character, then press:

```
a
```

`a` = "append". Typing now appears to the **right** of the cursor. This is
handy for adding to the end of a word instead of the front.

### o - open a new line below

```
o
```

`o` = "open line below". vi creates a fresh blank line under the current one,
moves the cursor there, and enters insert mode. Type:

```
this is a brand new line below
```

Press `Esc`.

### O - open a new line above

```
O
```

Capital `O` (hold Shift) = "open line above". Same as `o`, but the new line
appears above the current one. This is perfect for adding a comment line above
a config setting.

> **DBA Context - o for Config Comments:** When you edit `postgresql.conf`, you
> often want to add a comment that says why you changed a setting. Put your
> cursor on the setting line. Press `O` to open a line above. Type
> `# changed 2026-07-08 for connection tuning`. Press `Esc`. Clean, dated
> comments make the next DBA's life easier.

---

## 4. The Esc reflex

Every single time you finish typing, press `Esc`. Make it automatic. Here is
why it matters.

Say you are in insert mode and press `:`, hoping to run `:wq`. vi just types a
colon into your file. It does not save. Beginners then type `wq`, and now their
file has `:wq` in it as plain text. The fix is always the same. Press `Esc`
first, then type `:wq`.

Practice the reflex now. You should be in command mode. Press `i`, type a word,
and press `Esc`. Do it five times fast. Type, `Esc`, type, `Esc`. Building this
reflex is 80 percent of getting comfortable in vi.

Save what you have and quit:

```
:wq
```

`:w` writes the file, `q` quits.

Verify the file:

```bash
cat modes.txt
```

`cat` prints the file contents.

```
Expected output (yours will differ):
hello world
this is a brand new line below
```

---

## 5. A quick reference for entering insert mode

| Key | Name | Where typing starts |
|-----|------|---------------------|
| `i` | insert | Before the cursor |
| `a` | append | After the cursor |
| `I` | insert at line start | Before the first non-blank character on the line |
| `A` | append at line end | At the very end of the current line |
| `o` | open below | On a new blank line below |
| `O` | open above | On a new blank line above |

`A` (append at end of line) is a DBA favorite. Put the cursor anywhere on a
line, press `A`, and you are typing at the end of it right away. This is great
for adding a value to a config setting.

> **Concept - Capital Letters Mean "Bigger":** Notice the pattern. The capital
> version of a key usually does a "bigger" or "line-level" version of the
> lowercase one. `a` appends after one character; `A` appends at the end of the
> whole line. `o` opens one line below; `O` opens above. This pattern shows up
> all over vi. Once you spot it, you can guess commands you have not learned
> yet.

---

## 6. Prove you understand the modes

Do this small drill without looking at the notes. Open a file:

```bash
vi drill.txt
```

Then, in order:

1. Press `i`, type `line one`, press `Esc`.
2. Press `o`, type `line two`, press `Esc`.
3. Press `O`, type `line above line two`, press `Esc`.
4. Type `:wq` and press Enter.

Check the result:

```bash
cat drill.txt
```

```
Expected output (yours will differ):
line one
line above line two
line two
```

Does your output match (line one, then the "above" line, then line two)? Then
you have the mode model down. The `O` line landed above `line two` because that
is where your cursor was.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain the difference between command mode and insert mode in one sentence
- [ ] Name which mode vi starts in (command mode)
- [ ] Enter insert mode with `i` and confirm the `-- INSERT --` marker appears
- [ ] Use `a` to append after the cursor
- [ ] Use `o` to open a new line below and `O` to open one above
- [ ] Use `A` to jump to the end of a line and start typing
- [ ] Press `Esc` reflexively every time you finish typing
- [ ] Complete the mode drill and match the expected output

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
