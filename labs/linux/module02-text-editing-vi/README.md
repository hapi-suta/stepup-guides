# Module 02 - Text Editing with vi

vi is the text editor found on every Linux server. It is also the scariest
thing most beginners meet. This module makes it easy.

You will learn how vi's two modes work. You will learn how to open a file and,
most important, how to quit one. You will learn to move around, edit text, and
find and replace words in bulk. At the end, you will safely edit a real config
file the way a pro does.

Every skill here is one you will use as a DBA. You will edit files like
`postgresql.conf`, `pg_hba.conf`, `sshd_config`, and systemd unit files all
the time.

---

## Prerequisites

- Completion of Module 01 - Linux Fundamentals (or equivalent comfort with SSH
  and basic commands)
- Server access (CentOS Stream 9) - provided by your instructor
- SSH key from your welcome email
- A terminal application (Terminal on Mac, MobaXterm on Windows)

## Infrastructure

| Resource | Details |
|----------|---------|
| Nodes | 1 (your lab server) |
| OS | CentOS Stream 9 |
| SSH user | ec2-user |
| Editor | vi (runs vim on CentOS 9) |
| Package manager | dnf |

---

## Directory Structure

```
module02-text-editing-vi/
  build/          Step-by-step guided labs
  use/            Independent exercises
  survive/        Chaos scenarios to troubleshoot
  concepts/       Reference material
```

---

## Phases

### Phase 1 - BUILD

Work through these guides in order. Each one builds on the last. Do not skip
Guide 01. Knowing how to quit is what keeps you from ever feeling stuck.

| # | Guide | Time | Topics |
|---|-------|------|--------|
| 01 | [Opening and Quitting](build/01-opening-and-quitting.md) | 40 min | Why modes exist, `:q`, `:q!`, `:wq`, `ZZ`, the golden escape |
| 02 | [Command Mode and Insert Mode](build/02-insert-and-command-mode.md) | 40 min | The two-mode model, `i`/`a`/`o`/`O`, the `Esc` reflex |
| 03 | [Moving Around a File](build/03-moving-around.md) | 45 min | `h`/`j`/`k`/`l`, `w`/`b`, `0`/`$`, `gg`/`G`, `:n`, `Ctrl+f`/`Ctrl+b` |
| 04 | [Editing Text](build/04-editing-text.md) | 50 min | `x`, `dd`, `dw`, `yy`, `p`, undo `u`, redo `Ctrl+r`, `r`, `cw` |
| 05 | [Search and Replace](build/05-search-and-replace.md) | 45 min | `/pattern`, `n`/`N`, `:%s/old/new/g`, confirm with `c` |
| 06 | [Editing a Real Config File](build/06-editing-a-real-config.md) | 50 min | Backup, edit `sshd_config`, save, verify, validate - end to end |

### Phase 2 - USE

Complete these exercises without looking back at the BUILD guides.

| # | Exercise | Time | Focus |
|---|----------|------|-------|
| 01 | [Quit Drill](use/01-quit-drill.md) | 10-15 min | Open and exit files every way, no panic |
| 02 | [Movement Race](use/02-movement-race.md) | 15-20 min | Navigate a large file with no arrow keys |
| 03 | [Edit and Restore](use/03-edit-and-restore.md) | 20 min | Delete, copy, paste, and undo your way back |
| 04 | [Bulk Rename in a Config](use/04-bulk-rename.md) | 15-20 min | Search and replace with confirmation |
| 05 | [Config Change End to End](use/05-config-change.md) | 20 min | Backup, edit, verify, validate a real file |
| - | [Knowledge Checklist](use/checklist.md) | 15 min | Self-assessment before Phase 3 |

### Phase 3 - SURVIVE

Your instructor will inject a problem into your server. You must diagnose and
fix it using only the runbook and your BUILD knowledge.

| # | Scenario | Alert |
|---|----------|-------|
| 01 | [Trapped in Insert Mode](survive/01-trapped-in-insert-mode/) | Colon commands are ending up as text in the file |
| 02 | [Config Won't Validate](survive/02-config-wont-validate/) | sshd -t reports a syntax error after an edit |
| 03 | [Wrong Line Edited](survive/03-wrong-line-edited/) | A setting changed on the wrong line, service misbehaving |
| 04 | [Botched Bulk Replace](survive/04-botched-bulk-replace/) | A :%s replaced too much and broke the config |
| 05 | [Read-Only File](survive/05-readonly-file/) | Cannot save edits to a root-owned config |

### Concepts

| Document | Topics |
|----------|--------|
| [vi Modes and Cheat Sheet](concepts/vi-modes-and-cheatsheet.md) | The modes model, full command tables, DBA worked examples, beginner traps |

---

## Time Estimate

| Phase | Time |
|-------|------|
| BUILD | 4-5 hours |
| USE | 1.5-2 hours |
| SURVIVE | 2-3 hours |
| **Total** | **7.5-10 hours** |

Work at your own pace. Take breaks between BUILD guides. Do not rush. vi feels
strange for about an hour. Then it clicks, and it stays with you for life.

---

## Getting Help

If you get stuck:

1. Re-read the BUILD guide for the topic you are working on
2. Check the Concepts reference, especially the "Common Beginner Traps" table
3. Remember the golden escape sequence: `Esc` then `:q!`
4. Ask your instructor
