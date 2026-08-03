# SURVIVE: Loss Goes to NaN (Exploding Gradients)

A PyTorch text-classifier training script is supposed to drive the loss down
every epoch. Instead the loss jumps to a huge number, then `inf`, then `nan`,
and the model learns nothing. This is one of the most common ways deep learning
training fails, and it has a name: **exploding gradients**, almost always caused
by a learning rate that is too high.

In this runbook you will detect the blow-up, diagnose that the gradients are
exploding because the learning rate is too high, and recover the run - either by
lowering the learning rate, by turning on gradient clipping, or both.

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - understand WHY it is wrong.
3. Fix - repair it and verify the fix.

Server and user context: everything below runs on your lab server as the
`ec2-user` Linux user, on CentOS Stream 9 with Python 3.12. CPU only, no GPU.

---

## Layer 1: Detect

Move into the scenario working directory the injector created.

On your lab server, as ec2-user:

```
cd ~/survive-loss-nan
```

`cd` changes your current directory. `~` is your home directory
(`/home/ec2-user`), so this puts you inside the scenario folder.

Turn on the Python virtual environment that has PyTorch installed.

Still on your lab server, as ec2-user:

```
source venv/bin/activate
```

`source` runs the activation script in your current shell so the venv's Python
and packages are used. Your prompt will start with `(venv)`.

Expected output (yours will differ):

```
(venv) [ec2-user@ip-10-0-1-20 survive-loss-nan]$
```

Run the training script and watch the loss.

Still on your lab server, as ec2-user:

```
python train.py
```

`python` runs the script. Because the venv is active, this is Python 3.12 with
the CPU-only PyTorch.

Expected output (yours will differ):

```
epoch  0  loss 1.098612
epoch  5  loss 42.318771
epoch 10  loss 15330.964844
epoch 15  loss inf
epoch 20  loss nan
epoch 25  loss nan
epoch 35  loss nan
epoch 39  loss nan
FINAL_LOSS nan
```

The telltale signs of a broken run:

- The loss goes UP, fast, instead of down.
- It reaches `inf` (a number too big for the computer to hold).
- After `inf` the math produces `nan` ("not a number").
- The final line prints `FINAL_LOSS nan`.

A healthy run would show the loss shrinking each epoch and ending as a small
finite number. You have confirmed the failure.

---

## Layer 2: Diagnose

### What the script is trying to do

It builds TF-IDF features from a few short documents and trains a tiny neural
network to classify them into three types. Cross-entropy loss measures how wrong
the predictions are; gradient descent (here plain SGD) nudges the weights each
epoch to lower that loss (Concepts 5.1).

### What "exploding gradients" means

Each epoch, backprop computes a gradient for every weight - the direction and
size of the nudge that would lower the loss. The optimizer multiplies that
gradient by the **learning rate** and subtracts it from the weight. If the
learning rate is too big, the nudge overshoots the target, lands somewhere the
loss is even higher, and the NEXT gradient is bigger still. The gradients feed
on themselves and grow without bound - they **explode**. The weights race off to
enormous values, the loss overflows to `inf`, and any further math gives `nan`.

This is the same divergence you saw in Tier 2's gradient-descent scenario, now
inside a neural network. The cure is the same idea: take smaller steps.

### Confirm the cause: look at the learning rate

Still on your lab server, as ec2-user:

```
grep learning_rate train.py
```

`grep` searches a file for a word and prints the matching lines, so you can see
the learning rate without opening the whole file.

Expected output (yours will differ):

```
    # BUG: this learning rate is far too high and makes the loss diverge to nan.
    # A healthy value for this problem is around 0.05.
    learning_rate = 50.0
    optimizer = torch.optim.SGD(model.parameters(), lr=learning_rate)
```

The learning rate is `50.0`. For this problem that is enormous - roughly a
thousand times too big. Every step overshoots massively, so the gradients
explode and the loss blows up.

### Two independent fixes (you can use either or both)

- **Lower the learning rate.** The direct cause is the step size, so shrink it.
  A value around `0.05` converges cleanly here. This is the primary fix.
- **Gradient clipping.** Cap how large any single update can be, so even a big
  gradient cannot cause a giant jump. The script already contains a disabled
  clipping block (`use_grad_clip = False`); turning it on is a real-world safety
  net used in production training. On its own it helps, but with a learning rate
  as absurd as 50 you should ALSO lower the rate. The most robust answer is to
  do both: a sane learning rate AND clipping as insurance.

---

## Layer 3: Fix

You will lower the learning rate to `0.05` and turn on gradient clipping, then
rerun and confirm the loss converges to a small finite number.

Open the script in the vi editor.

On your lab server, as ec2-user:

```
vi train.py
```

`vi` is a text editor that runs in the terminal.

### Fix 1: lower the learning rate

Inside vi, search for the bad line. Type:

```
/learning_rate = 50.0
```

`/` starts a search in vi. Type the text and press Enter; the cursor jumps to
the `learning_rate = 50.0` line.

Enter insert mode. Press:

```
i
```

You will see `-- INSERT --` at the bottom. Edit the line so it reads exactly:

```
learning_rate = 0.05
```

Delete the `50.0` and type `0.05` in its place. Keep the rest of the line the
same.

### Fix 2: turn on gradient clipping

Leave insert mode by pressing the Escape key. Now search for the clipping flag.
Type:

```
/use_grad_clip = False
```

Press Enter; the cursor lands on the `use_grad_clip = False` line. Enter insert
mode again:

```
i
```

Change that line so it reads exactly:

```
use_grad_clip = True
```

Delete `False` and type `True`. Keep the rest the same.

Now leave insert mode and save. Press the Escape key, then type:

```
:wq
```

`Escape` leaves insert mode. `:wq` writes (saves) the file and quits vi. Press
Enter to run it.

Confirm both changes took effect.

Still on your lab server, as ec2-user:

```
grep -E "learning_rate = |use_grad_clip = " train.py
```

`grep -E` searches with an extended pattern; the pattern matches both lines so
you can verify them at once.

Expected output (yours will differ):

```
    learning_rate = 0.05
    use_grad_clip = True
```

Rerun the training script.

Still on your lab server, as ec2-user:

```
python train.py
```

Expected output (yours will differ):

```
epoch  0  loss 1.098612
epoch  5  loss 0.923217
epoch 10  loss 0.641044
epoch 15  loss 0.402118
epoch 20  loss 0.238905
epoch 25  loss 0.142773
epoch 35  loss 0.061204
epoch 39  loss 0.048915
FINAL_LOSS 0.048915
```

Signs of a healthy, recovered run:

- The loss now DECREASES every epoch instead of exploding.
- It ends as a small finite number.
- `FINAL_LOSS` prints a real number, not `inf` or `nan`.

You have stopped the exploding gradients and the model trains. That is the
survive.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validation script. It reruns your `train.py`, checks that it
exits cleanly, and checks that the final loss is a real, small number instead of
`inf`/`nan`.

Expected output (yours will differ):

```
Running your train.py ...
Final loss reported: 0.048915
PASS: training recovered (final loss 0.048915 is finite and below 1.0).
```

If you see `PASS`, you are done.

---

## Takeaways

- Loss climbing to `inf`/`nan` means the gradients exploded - almost always the
  learning rate is too high.
- The direct fix is to lower the learning rate (take smaller steps).
- Gradient clipping caps the size of any single update; it is a production safety
  net against exploding gradients and works well alongside a sane learning rate.
- The most robust recovery uses both: a reasonable learning rate AND clipping.
- This is the same divergence idea from Tier 2, now inside a neural network - the
  cure is always smaller, safer steps.

Prof. Happy (SUTA Labs)
