# Build 03: Moving Around a File

You will learn to move the cursor without arrow keys. You can move by character,
by word, by line, and jump to the top or bottom of a file. Moving fast matters.
It is what makes editing a 1,000-line `postgresql.conf` bearable.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. First, a file worth moving through

To practice moving around, you need a file with real content. Let's copy a
system file into your practice folder. That way you cannot damage the original.

Move into your practice folder:

```bash
cd ~/vi-practice
```

Copy the SSH config into it. The file is owned by root, so the copy needs
`sudo`:

```bash
sudo cp /etc/ssh/sshd_config move-practice.txt
```

`sudo cp` copies a file as root. The first path is the source
(`/etc/ssh/sshd_config`). The second is where the copy goes
(`move-practice.txt`) in your current folder. You are working on a copy, so the
real config is never at risk.

The copy is still owned by root. Change it to be owned by you so you can open
and edit it as **ec2-user**:

```bash
sudo chown ec2-user:ec2-user move-practice.txt
```

`chown` changes the owner of a file. Now `move-practice.txt` belongs to you.

Open the copy:

```bash
vi move-practice.txt
```

You are in command mode. All the movement keys below work only in command mode.
So if typing letters changes the text, press `Esc` first.

---

## 2. Move by character: h j k l

vi's original movement keys are `h`, `j`, `k`, `l`. They sit right under your
right hand on the home row. So you never have to reach for the arrow keys.

Press each one a few times and watch the cursor:

- `h` - move **left** one character
- `j` - move **down** one line
- `k` - move **up** one line
- `l` - move **right** one character

Here is a memory trick. `j` looks a bit like a down arrow, since it has a hook
at the bottom. `h` is on the far left, so it goes left. `l` is on the right, so
it goes right.

The arrow keys usually work too in vim on CentOS 9. But `hjkl` is faster once
your fingers learn it. It also works on old terminals where arrow keys do not.

> **Concept - Counts Before Commands:** Almost every movement key can take a
> number in front of it. `5j` moves down 5 lines. `10l` moves right 10
> characters. This "count then command" pattern shows up all over vi. It lets
> you jump an exact distance without holding a key down.

Try it: type `5j` and the cursor jumps down five lines at once.

---

## 3. Move by word: w and b

Moving one character at a time is slow. Move by whole words instead:

- `w` - jump forward to the start of the next **w**ord
- `b` - jump **b**ackward to the start of the previous word
- `e` - jump to the **e**nd of the current or next word

Press `w` several times and watch the cursor hop from word to word. Press `b` to
go back. These keys count punctuation as words too. So in `port = 22`, the `=`
counts as its own word.

Counts work here too: `3w` jumps forward three words.

---

## 4. Move within a line: 0 and $

Two keys jump to the ends of the current line:

- `0` (the number zero) - jump to the very **start** of the line (column 1)
- `$` (dollar sign, Shift+4) - jump to the **end** of the line

These are instant no matter how long the line is. Use `0` to jump to the start
of a config line and read the parameter name. Use `$` to jump to the end and add
a value.

There is also `^` (caret). It jumps to the first character that is not a blank
space. It skips any spaces or tabs at the start of the line. On an indented
line, `^` is often more useful than `0`.

---

## 5. Move through the whole file: gg and G

For big files, you need to leap to the top or bottom:

- `gg` - jump to the **first** line of the file
- `G` (capital, Shift+g) - jump to the **last** line of the file

Press `G` and the cursor drops to the end of `move-practice.txt`. Press `gg`
and it snaps back to line 1.

You can also jump to a specific line number by putting the number before `G`:

- `25G` - jump to line 25

> **DBA Context - Jumping to an Error Line:** When PostgreSQL fails to start, it
> often tells you exactly where: `syntax error in file "postgresql.conf" line
> 64`. Open the file and type `64G`. You land on that line right away. No
> scrolling, no counting. This one trick saves real time during an outage.

---

## 6. Jump to a line with :n

There is a second way to jump to a line. It uses an ex command, which is one of
the colon commands from Build 01. Type a colon, then the line number, then
Enter:

```
:64
```

- `:` - open the command line at the bottom
- `64` - the line number to jump to
- Enter - go there

This does the same thing as `64G`. Some people find `:64` easier to remember,
because it reads like "go to line 64". Use whichever one sticks for you.

Want to see your current position? Glance at the bottom-right of the screen in
vim. It shows something like `64,1`, which means line 64, column 1.

---

## 7. Scroll a screen at a time: Ctrl+f and Ctrl+b

When a file is longer than your terminal window, you need to scroll:

- `Ctrl+f` - scroll **f**orward one full screen (page down)
- `Ctrl+b` - scroll **b**ackward one full screen (page up)

Hold `Ctrl` and press `f`, then `b`. These move a whole screen at a time. That
is faster than `j` and `k` for covering distance. Two gentler keys move half a
screen:

- `Ctrl+d` - scroll **d**own half a screen
- `Ctrl+u` - scroll **u**p half a screen

None of these change your file. They only move your view. So they are safe to
press as much as you want while you explore.

---

## 8. Put it together

Take this tour of the file without arrow keys. Make sure you are in command mode
first (press `Esc` if you are not sure):

1. Press `gg` to go to the top.
2. Press `G` to go to the bottom.
3. Type `10G` to jump to line 10.
4. Press `$` to go to the end of that line, then `0` to snap back to the start.
5. Press `w` a few times to hop across words, then `b` to come back.
6. Press `Ctrl+f` to page down, then `Ctrl+b` to page up.

You did not change a single character. It was all movement, no edits. Quit
without saving to prove nothing changed:

```
:q
```

Because you made no edits, plain `:q` works with no error. If it complains, you
typed into the file by accident. Press `Esc` and use `:q!` instead.

---

## 9. Movement quick reference

| Key | Moves cursor to |
|-----|-----------------|
| `h` `j` `k` `l` | Left, down, up, right (one step) |
| `w` / `b` | Start of next word / previous word |
| `e` | End of the current or next word |
| `0` / `$` | Start / end of the current line |
| `^` | First non-blank character on the line |
| `gg` / `G` | First line / last line of the file |
| `NG` or `:N` | Line number N (e.g. `64G` or `:64`) |
| `Ctrl+f` / `Ctrl+b` | Forward / back one full screen |
| `Ctrl+d` / `Ctrl+u` | Down / up half a screen |

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Move by character with `h`, `j`, `k`, `l` (no arrow keys)
- [ ] Jump word to word with `w` and `b`
- [ ] Jump to the start of a line with `0` and the end with `$`
- [ ] Jump to the top of a file with `gg` and the bottom with `G`
- [ ] Jump to a specific line with `NG` (e.g. `25G`) and with `:N` (e.g. `:25`)
- [ ] Use a count before a movement, like `5j`
- [ ] Scroll a full screen with `Ctrl+f` and `Ctrl+b`
- [ ] Explain how you would jump straight to an error line reported by PostgreSQL

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.
