# USE: Machine-Learning Use-Case Evaluation Template

**Tier 4 - USE phase.** In this exercise you build a reusable consulting artifact: a "Machine-Learning Use-Case Evaluation Template". This is a document you fill in BEFORE you write any model code, to decide whether machine learning is even the right tool, and if it is, how to build and ship it responsibly. Good consultants say "no" to bad ML ideas early. This template is how you do that on paper, cheaply, before a client spends money.

**Validated on:** CentOS Stream 9, Python 3.12, on 2026-07-25.

**Prerequisite:** You have finished the Tier 4 BUILD phase (you have trained at least one classifier and know what precision, recall, and a baseline are). You are logged into your lab server and can edit files with vi.

**Goal:** Create a blank evaluation template you can reuse for any client, then fill it in for a worked example (customer-churn prediction) so you see the thinking applied. This is mostly writing and reasoning - very little code.

---

## Step 1: Log in and go to your home directory

On your **lab server**, as **ec2-user**:

```
cd ~
```

The `cd` command means "change directory". With no arguments and `~` it takes you to your home directory, which is a safe, writable place to keep your work.

Expected output (yours will differ):

```
[ec2-user@lab-server ~]$
```

There is no message - a bare prompt ending in `~` means you are home.

---

## Step 2: Make a folder to hold your consulting artifacts

On your **lab server**, as **ec2-user**:

```
mkdir -p ~/ml-artifacts
```

The `mkdir` command makes a new directory. The `-p` flag means "create parent folders if needed and do not error if it already exists", so this is safe to run twice.

Then move into it:

```
cd ~/ml-artifacts
```

Expected output (yours will differ):

```
[ec2-user@lab-server ml-artifacts]$
```

The prompt now ends in `ml-artifacts`, confirming you are inside the new folder.

---

## Step 3: Create the blank template file with vi

On your **lab server**, as **ec2-user**:

```
vi ml-usecase-template.md
```

The `vi` command opens the vi text editor. Because the file does not exist yet, vi opens an empty screen ready for a new file named `ml-usecase-template.md`.

Press `i` and enter:

```
# ML Use-Case Evaluation Template

Fill this in BEFORE building any model. If more than one or two
sections come back weak, machine learning is probably the wrong tool
for this problem. Say so.

## 1. Business objective
What business outcome are we trying to move? State it in money, time,
or risk terms, not in model terms. Example: "reduce monthly customer
cancellations" not "build a churn model".

## 2. Prediction target
Exactly what does the model output, one row at a time? Name the unit
(a customer, an order, a login), the thing predicted (yes/no, a
number, a category), and the time horizon (in the next 30 days?).
If you cannot write this in one clear sentence, stop.

## 3. Available data
- What data exists today, and where does it live?
- Quality: how clean, how many missing values, how trustworthy?
- Volume: how many rows, how many examples of the rare thing?
- Labels: do we have the answer (the truth) for past cases? A model
  that predicts churn needs historical records of who actually churned.
  No labels usually means no supervised ML.

## 4. Baseline (the thing to beat)
What is the dumb or current approach? Examples: "always guess the most
common answer", "use the rule the ops team already uses", "guess at
random". If ML cannot clearly beat the dumb baseline, it is not worth
the cost and complexity. Write the baseline's expected number here.

## 5. Cost of mistakes
Models are wrong sometimes. Two kinds of wrong:
- False positive: we predicted yes, truth was no. Business cost?
- False negative: we predicted no, truth was yes. Business cost?
State both in real terms (dollars, a lost customer, a wrongly blocked
payment). These costs decide how we tune the model later.

## 6. Human oversight
- Who looks at the predictions, and how often?
- Can a human override the model, and how?
- Is the model advising a person, or acting on its own?
The higher the cost of mistakes, the more human review you need.

## 7. Legal and ethical risk
- Bias: could the model treat groups unfairly?
- Proxy variables: does an innocent-looking feature (zip code, device)
  secretly stand in for a protected trait (race, age)?
- Regulation: does any law govern this decision (credit, hiring,
  health, lending)?
- Privacy: are we using data people did not agree to be used this way?
If any of these is a "maybe", flag it and get a human owner.

## 8. Success metrics
Which single metric decides success, and what target must it hit? Tie
it to the business, not just to accuracy. Example: "catch 70 percent
of churners (recall) while keeping outreach cost acceptable". Name the
metric AND the number.

## 9. Deployment
- How do predictions actually reach the people who use them (a report,
  an API, a dashboard, an alert)?
- Latency: does the answer need to be instant or is overnight fine?
- Retraining cadence: how often do we refresh the model as the world
  changes (monthly, quarterly)? Who owns that job?
```

Press `Esc`, type `:wq`, press Enter.

The `Esc` key leaves insert mode. Typing `:wq` then Enter tells vi to write (save) the file and quit.

---

## Step 4: Confirm the template saved

On your **lab server**, as **ec2-user**:

```
wc -l ml-usecase-template.md
```

The `wc` command counts things in a file. The `-l` flag counts lines, so you can confirm the file has content and was not saved empty.

Expected output (yours will differ):

```
78 ml-usecase-template.md
```

Any number well above zero means your template saved correctly.

---

## Step 5: Copy the template for a worked example

You never edit the master template when doing real work - you copy it, then fill in the copy. On your **lab server**, as **ec2-user**:

```
cp ml-usecase-template.md churn-example.md
```

The `cp` command copies a file. The first name is the source, the second is the new copy. Now you have a fresh `churn-example.md` to fill in for a real scenario.

Expected output (yours will differ):

```
[ec2-user@lab-server ml-artifacts]$
```

No output means the copy succeeded. You can verify with `ls`:

```
ls
```

Expected output (yours will differ):

```
churn-example.md  ml-usecase-template.md
```

Both files are present.

---

## Step 6: Fill in the worked example (customer churn)

The scenario: a subscription business (a meal-kit company) wants to predict which customers will cancel in the next 30 days so the retention team can call them first. Open the copy. On your **lab server**, as **ec2-user**:

```
vi churn-example.md
```

vi opens your copied file, showing the same section headings. You will replace the guidance text under each heading with real answers.

Press `i`, then use the arrow keys and normal typing to replace the file contents so it reads like this (delete the old guidance lines as you go, or just clear the file and type this in fresh):

```
# ML Use-Case Evaluation: Customer Churn (Meal-Kit Co.)

## 1. Business objective
Reduce the number of customers who cancel their subscription each
month. Every retained customer is worth about 480 dollars a year.
Even a small drop in cancellations pays for the project.

## 2. Prediction target
Unit: one active customer. Output: probability that this customer
cancels within the next 30 days (a number from 0 to 1). We will turn
that number into a yes/no using a threshold we choose later.

## 3. Available data
- Where: the orders and subscriptions tables in Postgres.
- Quality: good. Order history is clean; support-ticket text is messy
  and we will skip it for version 1.
- Volume: about 60,000 active customers, 24 months of history.
- Labels: yes. We know who cancelled in each past month, so we can
  train a supervised model. This is the strongest part of the case.

## 4. Baseline (the thing to beat)
Current approach: the retention team calls customers at random when
they have spare time. Random calling catches roughly the base churn
rate (about 8 percent) among the people it happens to call. Our model
must clearly do better than "call at random" to be worth building.

## 5. Cost of mistakes
- False positive: we flag a happy customer as a churn risk. Cost: one
  wasted retention call (a few dollars of staff time). Low.
- False negative: we miss a customer who then cancels. Cost: up to
  480 dollars in lost yearly value. High.
Because misses cost far more than false alarms, we will tune the model
toward catching more churners (recall), even if that means more false
alarms.

## 6. Human oversight
The model does not cancel or discount anything. It produces a ranked
call list. A retention agent reviews each name and decides how to
reach out. A human is always in the loop, so the risk from a wrong
prediction is just a wasted call.

## 7. Legal and ethical risk
- Bias: retention offers must not vary by protected traits. We will
  not use age, gender, or race as features.
- Proxy variables: zip code could stand in for income or ethnicity, so
  we exclude raw zip code.
- Regulation: this is marketing outreach, not credit or hiring, so
  regulatory load is light. Still, offers must be applied consistently.
- Privacy: we only use data the customer already gave us as part of
  the subscription. No third-party data.

## 8. Success metrics
Primary metric: recall on churners, target 70 percent (catch 7 of
every 10 customers who would have cancelled). Guardrail: keep the
call list small enough that the team can actually work it (no more
than 15 percent of customers flagged per month). Tie-back: even a
5-point drop in monthly churn pays for the whole project.

## 9. Deployment
- Delivery: a nightly job writes a ranked "at-risk" list to a
  dashboard the retention team already uses.
- Latency: overnight is fine. This is not real-time.
- Retraining: refresh the model monthly, because customer behavior and
  promotions change. The data team owns the monthly retrain job.
```

Press `Esc`, type `:wq`, press Enter.

You saved a complete, filled-in evaluation for a real use case.

---

## Step 7: Read your finished example back

On your **lab server**, as **ec2-user**:

```
cat churn-example.md
```

The `cat` command prints a file's contents to the screen so you can read the whole thing at once and check it makes sense.

Expected output (yours will differ):

```
# ML Use-Case Evaluation: Customer Churn (Meal-Kit Co.)

## 1. Business objective
Reduce the number of customers who cancel their subscription each
month. Every retained customer is worth about 480 dollars a year.
...
## 9. Deployment
- Delivery: a nightly job writes a ranked "at-risk" list ...
```

You should see all nine sections filled with real answers.

---

## Step 8: Reflection (write your judgment)

The template exists to help you make one decision: build or do not build. Add your verdict to the bottom of the example. On your **lab server**, as **ec2-user**:

```
vi churn-example.md
```

Press `G` to jump to the last line of the file. The capital `G` in vi moves the cursor to the end of the file. Then press `o` to open a new line below and enter insert mode, and type:

```

## Verdict
BUILD. All nine sections are strong: clear money objective, a clean
one-sentence target, labeled data at good volume, an easy baseline to
beat, low downside on false positives, a human always in the loop, and
manageable ethical risk. The model advises people, it does not act
alone, so the worst mistake is a wasted phone call. This is a
responsible, worthwhile ML project.
```

Press `Esc`, type `:wq`, press Enter.

Now think about the opposite case for a moment. If this client had NO record of who cancelled in the past (no labels), or if a simple rule like "anyone who skipped their last two deliveries" already caught most churners, the honest verdict would be DO NOT BUILD - a lookup or a rule would be cheaper and just as good. That "no" is often the most valuable thing a consultant delivers.

---

## What you produced

- `~/ml-artifacts/ml-usecase-template.md` - a reusable blank template for any client.
- `~/ml-artifacts/churn-example.md` - a fully worked, decided example.

Reuse the template on every future engagement. Filling it in takes an hour and can save a client months of building the wrong thing.
