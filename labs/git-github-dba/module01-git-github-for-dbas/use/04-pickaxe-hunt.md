# Exercise 04: The Pickaxe Hunt

**Duration:** 15 minutes
**Objective:** Search HISTORY (not files) for every change that ever touched a setting, using git log -S and per-file patch history.
**Prerequisites:** Exercises 01-03 completed. Single node. Work as **postgres** on **pg-single**.

## Background

`grep` tells you what a file says NOW. Only git can tell you every time a setting was touched, across all files, ever. The tool is `git log -S` (nicknamed "the pickaxe"): it finds commits whose DIFF contains a string.

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

## Question 1: Every commit that ever touched work_mem

### Try it

```bash
git log -S'work_mem' --oneline
```

Expected output (yours will differ):

```
9c60ab4 raise maintenance_work_mem for reindex window
f6759b8 raise work_mem to 8MB via ALTER SYSTEM
4675838 baseline: configs as provisioned
```

Three matches. Two are obvious - but why does the BASELINE commit match? Because `-S` matches the string anywhere in the diff, and the baseline added postgresql.conf, whose comments mention work_mem. And `maintenance_work_mem` contains `work_mem` as a substring. Lesson: the pickaxe is a metal detector, not a scalpel - read what it finds.

## Question 2: The full patch history of one file

postgresql.auto.conf is the file postgres itself writes. Show every change it has ever received, with the actual diffs:

### Try it

```bash
git log -p --oneline -- postgresql.auto.conf
```

Expected output (yours will differ):

```
9c60ab4 raise maintenance_work_mem for reindex window
...
+maintenance_work_mem = '128MB'
f6759b8 raise work_mem to 8MB via ALTER SYSTEM
...
+work_mem = '8MB'
```

Every ALTER SYSTEM this server has ever run, in order, with timestamps and authors. (Press `q` to leave the pager.)

## Question 3: Narrow the pickaxe

Find only the commits where the LINE `work_mem = '8MB'` itself was added or removed - not comments, not substrings:

### Try it

```bash
git log -S"work_mem = '8MB'" --oneline
```

One match this time. Precision comes from searching for the exact line.

## Question 4 (thought exercise)

Security asks: "was password_encryption ever changed on this server?" Write the exact command you would run, then run it and interpret the result.
