# Exercise 01: The Blame Hunt

**Duration:** 15 minutes
**Objective:** Answer "who changed this setting, when, and what else changed with it" using only git.
**Prerequisites:** BUILD guide 04 completed. Single node. All work as **postgres** on **pg-single**.

## Background

An auditor (or your own 2am brain) asks: "shared_buffers is 256MB on this server. Who set that, when, and was it reviewed?" On an unversioned server this takes an hour of guessing. On yours it takes three commands.

Switch to the postgres user and enter the repo:

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

## Question 1: Which commit last touched the shared_buffers line?

### Try it

```bash
git blame postgresql.conf | grep shared_buffers
```

Expected output (yours will differ):

```
c6c84d47 (Felicite Nji 2026-08-13 01:05:40 +0000 130) shared_buffers = 256MB			# min 128kB
^4675838 (... 237) #wal_buffers = -1			# min 32kB, -1 sets based on shared_buffers
```

The first line is the answer: commit `c6c84d4`, with author and timestamp. (The second hit is just a comment that mentions shared_buffers - read your matches.)

## Question 2: What exactly did that commit change - and ONLY that commit?

### Try it

```bash
git show c6c84d4
```

(Use YOUR commit ID from question 1.) Read the diff: one line changed, 128MB to 256MB. Nothing else was smuggled in with it. That is what a reviewable change looks like.

## Question 3: List every commit that ever touched postgresql.conf

### Try it

```bash
git log --oneline -- postgresql.conf
```

Expected output (yours will differ):

```
db8eaa3 Revert "increase max_connections for the new app"
10e95e7 increase max_connections for the new app
c6c84d4 raise shared_buffers to 256MB
4675838 baseline: configs as provisioned
```

The `-- postgresql.conf` limits history to one file. Note what you can read straight off this list: the mistake and its revert, sitting together in the record.

## Question 4 (thought exercise)

Your manager asks the same question about a server WITHOUT git: "who changed shared_buffers?" Write down (one sentence) what your honest answer would be. That sentence is why this module exists.
