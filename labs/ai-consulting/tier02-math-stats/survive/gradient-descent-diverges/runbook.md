# SURVIVE: Gradient Descent Diverges

A gradient descent training script is supposed to fit a straight line to some
noisy data. Instead of the loss shrinking toward zero, the loss grows every
epoch and blows up to `inf` and then `nan`. Your model parameters `w` and `b`
become `nan` too, so the model has learned nothing.

This is a classic training failure called **divergence**. In this runbook you
will detect it, diagnose the real cause (a bad learning rate), and fix it so
the loss actually converges.

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - understand WHY it is wrong.
3. Fix - repair it and verify the fix.

Server and user context: everything below runs on your lab server as the
`ec2-user` Linux user, on CentOS Stream 9 with Python 3.12.

---

## Layer 1: Detect

First, move into the scenario working directory that the injector created.

On your lab server, as ec2-user:

```
cd ~/survive-gd-diverges
```

`cd` changes your current directory. `~` is a shortcut for your home
directory (`/home/ec2-user`), so this puts you inside the scenario folder.

Now turn on the Python virtual environment that has numpy installed.

Still on your lab server, as ec2-user:

```
source venv/bin/activate
```

`source` runs the activation script in your current shell so the venv's Python
and packages are used. After this your prompt will start with `(venv)`.

Expected output (yours will differ):

```
(venv) [ec2-user@ip-10-0-1-20 survive-gd-diverges]$
```

Now run the training script and watch what the loss does.

Still on your lab server, as ec2-user:

```
python train.py
```

`python` runs the script. Because the venv is active, this is Python 3.12.

Expected output (yours will differ):

```
epoch  0  loss 508.371240  w 89.821719  b 12.550000
epoch  1  loss 92564.164062  w -1243.874219  b -173.905000
epoch  2  loss 17263840.000000  w 16972.981523  b 2376.482
...
epoch 28  loss inf  w nan  b nan
epoch 29  loss nan  w nan  b nan
FINAL_LOSS nan
```

The telltale signs of a broken run:

- The loss goes UP every epoch instead of down.
- It quickly reaches `inf` (a number too big for the computer to hold).
- After `inf` the math produces `nan` ("not a number").
- The final line prints `FINAL_LOSS nan`.

A healthy run would show the loss getting SMALLER each epoch and ending as a
small finite number. You have confirmed the failure. This is divergence.

---

## Layer 2: Diagnose

### What gradient descent is trying to do

The script fits a line `y = w*x + b` to noisy data. It measures how wrong the
line is with the mean squared error (MSE) loss - the average of the squared
gaps between the predicted `y` and the real `y`. Gradient descent nudges `w`
and `b` a little bit each epoch in the direction that makes the loss smaller.

### The step size is the learning rate

The size of that nudge is controlled by one setting: the **learning rate**.
This connects directly to Concepts 2.5 - the learning rate is the step size
gradient descent takes downhill on the loss surface. Picture walking downhill
in fog toward the lowest point of a valley:

- Too-small steps: you creep down so slowly you never reach the bottom in the
  time you have. This is **stalling**.
- Too-big steps: you leap right over the bottom and land higher up the far
  slope. Next step you leap back and land even higher. You bounce outward
  forever. This is **divergence**.

### Why THIS run diverges

Look at the setting in the script.

Still on your lab server, as ec2-user:

```
grep learning_rate train.py
```

`grep` searches a file for a word and prints the matching lines. This shows
you the current learning rate without opening the whole file.

Expected output (yours will differ):

```
    # BUG: this learning rate is far too large for this data and diverges.
    # A good value for this problem is around 0.01.
    learning_rate = 0.5
    w = w - learning_rate * grad_w
    b = b - learning_rate * grad_b
```

The learning rate is `0.5`. For this data (x runs from 0 to 10), the gradients
are large, so multiplying them by `0.5` produces a giant update. Each step
overshoots the true values (`w=2`, `b=5`) and lands further away than before.
The next step overshoots even harder. The loss grows without bound until the
numbers overflow to `inf`, and then any further math gives `nan`.

### How to tell divergence from stalling

Both are learning-rate problems, but they look different:

- **Divergence** (too high): loss INCREASES, reaches `inf`, then `nan`. This is
  what you are seeing now.
- **Stalling** (too low): loss barely moves - it decreases by a tiny amount or
  stays almost flat for all epochs and never gets near a good fit. If you fixed
  this by setting the learning rate to something like `0.00001`, you would see
  the loss inch down so slowly that `w` and `b` never reach 2 and 5.

The fix for divergence is to LOWER the learning rate. The fix for stalling is
to RAISE it. Your job here is the first one.

---

## Layer 3: Fix

You will lower the learning rate from `0.5` to a healthy `0.01`, then rerun and
confirm the loss converges.

Open the script in the vi editor.

On your lab server, as ec2-user:

```
vi train.py
```

`vi` is a text editor that runs right in the terminal.

Inside vi, find the line with the learning rate. Type the following to search:

```
/learning_rate = 0.5
```

`/` starts a search in vi. Type the text you want to find, then press Enter.
The cursor jumps to the `learning_rate = 0.5` line.

Now put vi into insert mode so you can type. Press:

```
i
```

Pressing `i` enters insert mode. You will see `-- INSERT --` at the bottom of
the screen. Edit the line so it reads exactly:

```
learning_rate = 0.01
```

Delete the `0.5` and type `0.01` in its place. Keep the rest of the line the
same.

Now leave insert mode and save. Press the Escape key, then type:

```
:wq
```

Pressing `Escape` leaves insert mode. `:wq` means write (save) the file and
quit vi. Press Enter to run it.

Confirm the change took effect.

Still on your lab server, as ec2-user:

```
grep "learning_rate =" train.py
```

Expected output (yours will differ):

```
    learning_rate = 0.01
```

Now rerun the training script.

Still on your lab server, as ec2-user:

```
python train.py
```

Expected output (yours will differ):

```
epoch  0  loss 508.371240  w 1.796434  b 0.251000
epoch  1  loss 42.719688  w 2.093846  b 0.331815
epoch  2  loss 34.114201  w 2.052312  b 0.401272
...
epoch 28  loss 1.284530  w 2.019987  b 4.870114
epoch 29  loss 1.221093  w 2.019430  b 4.909721
FINAL_LOSS 1.221093
```

Signs of a healthy, converged run:

- The loss now DECREASES every epoch instead of exploding.
- `w` settles near `2.0` and `b` climbs toward `5.0` - those match the true
  line `y = 2x + 5` the data came from.
- The final loss is a small finite number, and `FINAL_LOSS` prints a real
  number (not `inf` or `nan`).

You have fixed the learning rate and the model converges. That is the survive.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validation script. It reruns your `train.py`, checks that it
exits cleanly, and checks that the final loss is a real, small number instead
of `inf`/`nan`.

Expected output (yours will differ):

```
Running your train.py ...
Final loss reported: 1.221093
PASS: training converged (final loss 1.221093 is finite and below 50).
```

If you see `PASS`, you are done.

---

## Takeaways

- Loss climbing to `inf`/`nan` means the training diverged - almost always the
  learning rate is too high.
- Loss that barely moves means it stalled - the learning rate is too low.
- The learning rate is the step size (Concepts 2.5). Tune it: lower it to stop
  divergence, raise it to escape a stall.
- A good fit here drives `w` toward 2 and `b` toward 5, matching the true line
  the data was generated from.

Prof. Happy (SUTA Labs)
