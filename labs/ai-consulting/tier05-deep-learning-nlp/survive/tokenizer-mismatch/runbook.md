# SURVIVE: Tokenizer Mismatch (Train and Inference Use Different Feature Spaces)

This is the most dangerous NLP bug you will meet, because **nothing crashes.**
Training runs. The model saves. Prediction runs and returns confident answers.
But the answers are wrong, and no error, no traceback, no warning tells you.
Accuracy silently collapses.

The cause: the prediction code builds a BRAND-NEW tokenizer/vectorizer and fits
it on the new text, instead of reusing the exact vectorizer that training
learned. The training model expects features in one vocabulary and column order;
inference feeds it a different vocabulary and order. The model receives garbage
that happens to be the right shape, so it produces garbage confidently.

In this runbook you will detect the silent accuracy collapse, diagnose the
train/inference tokenizer mismatch, and fix it by reusing the SAVED vectorizer at
prediction time (Concepts 5.3: clean and featurize the SAME way at training and
inference).

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
cd ~/survive-tokenizer-mismatch
```

`cd` changes your current directory. `~` is your home directory.

Turn on the virtual environment that has PyTorch installed.

Still on your lab server, as ec2-user:

```
source venv/bin/activate
```

Your prompt starts with `(venv)`.

The model is already trained (the injector did it). Run the accuracy self-check.

Still on your lab server, as ec2-user:

```
python check.py
```

`python` runs the self-check, which classifies six held-out documents whose true
labels are known and reports accuracy.

Expected output (yours will differ):

```
XX  pred=resume   true=invoice   invoice amount due payment remittance enc
XX  pred=contract true=invoice   facture paiement solde montant
XX  pred=invoice  true=resume    resume skills senior engineer references
OK  pred=resume   true=resume    competences formation ingenieur experience
XX  pred=resume   true=contract  agreement parties terms notice governing
XX  pred=contract true=contract  contrat termes conditions parties droit
ACCURACY 0.3333
INFER_VOCAB 22  TRAIN_VOCAB 31
```

The telltale signs:

- The script did NOT crash - it ran to completion and printed answers.
- The predictions are mostly wrong. Accuracy is `0.33` - barely better than
  random guessing among three classes.
- The last line is the smoking gun: `INFER_VOCAB 22` but `TRAIN_VOCAB 31`. The
  vocabulary used at inference is a DIFFERENT SIZE from the one used at training.

A correctly wired classifier on this easy, keyword-heavy data should be near
100%. Accuracy at chance with two different vocab sizes means the model is being
fed features from a different feature space than it learned on. You have
confirmed a tokenizer mismatch.

---

## Layer 2: Diagnose

### Why this is silent

A TF-IDF vectorizer turns text into a fixed-width vector, one column per word in
its vocabulary. The model's first layer expects those columns in the EXACT order
the training vectorizer produced them. If inference uses a different vectorizer:

- The vocabulary differs (some training words missing, some new words present).
- The column ORDER differs, so column 5 might be "invoice" at training but
  "parties" at inference.
- The width can even differ, which forces a hack (padding/truncating) to make
  the shapes fit.

None of that raises an error - the numbers are still valid floats of a workable
shape - so the model happily multiplies garbage by its weights and outputs a
confident, wrong class. This is why tokenizer/feature mismatches are so feared in
production: your dashboards look fine, the service returns 200 OK, and quietly
every prediction is wrong.

### Find the bug in the code

Look at how the check script builds its features.

Still on your lab server, as ec2-user:

```
grep -nE "TfidfVectorizer|fit_transform|pickle|load" check.py
```

`grep -n` prints matching lines with line numbers so you can see exactly how
features are made at inference time.

Expected output (yours will differ):

```
7:from sklearn.feature_extraction.text import TfidfVectorizer
20:wrong_vectorizer = TfidfVectorizer()
21:Xbad = wrong_vectorizer.fit_transform(texts).toarray()
```

There it is. `check.py` creates a fresh `TfidfVectorizer()` and calls
`fit_transform` on the TEST texts. `fit_transform` LEARNS a new vocabulary from
the test data. It never touches the `vectorizer.pkl` that training saved.

Confirm training DID save the right vectorizer to reuse.

Still on your lab server, as ec2-user:

```
ls -1 vectorizer.pkl model.pt
```

`ls -1` lists the files one per line.

Expected output:

```
model.pt
vectorizer.pkl
```

The correct vectorizer is sitting right there on disk. The fix is to load and
reuse it instead of fitting a new one.

---

## Layer 3: Fix

The rule: **fit the vectorizer once, at training time, save it, and only ever
`transform` (never `fit`) with it afterward.** We will load the saved vectorizer
and call `transform` instead of building a new one and calling `fit_transform`.

Open the check script in vi.

On your lab server, as ec2-user:

```
vi check.py
```

### Fix: load and reuse the saved vectorizer

Search for the bad line.

```
/wrong_vectorizer = TfidfVectorizer()
```

`/` starts a search; press Enter to jump to it. The two bad lines are:

```
wrong_vectorizer = TfidfVectorizer()
Xbad = wrong_vectorizer.fit_transform(texts).toarray()
```

Delete both lines. With the cursor on the `wrong_vectorizer =` line, type:

```
2dd
```

`2dd` deletes 2 lines starting at the cursor.

Now enter insert mode to add the correct version. Press:

```
i
```

Type these lines (load the saved vectorizer, then TRANSFORM - not fit):

```python
import pickle
with open("vectorizer.pkl", "rb") as f:
    vectorizer = pickle.load(f)
Xbad = vectorizer.transform(texts).toarray()
```

`transform` uses the ALREADY-LEARNED vocabulary and column order. No new
vocabulary is created, so the features line up with what the model trained on.

Press the Escape key to leave insert mode.

### Remove the shape hack (optional but clean)

Because the features now match the trained width, the padding/truncating hack is
dead code. Leaving it in does no harm (the widths already match), so you may skip
this. If you want it clean, search for it:

```
/Force the mismatched features
```

Press Enter. The block from the `if num_features_at_infer < trained_features:`
line through the `Xbad = Xbad[:, :trained_features]` line is now unnecessary. You
can delete those 4 lines with the cursor on the `if` line by typing `4dd`. This
step is optional.

Now save and quit. Type:

```
:wq
```

Press Enter.

### Rerun the self-check

Still on your lab server, as ec2-user:

```
python check.py
```

Expected output (yours will differ):

```
OK  pred=invoice  true=invoice   invoice amount due payment remittance enc
OK  pred=invoice  true=invoice   facture paiement solde montant
OK  pred=resume   true=resume    resume skills senior engineer references
OK  pred=resume   true=resume    competences formation ingenieur experience
OK  pred=contract true=contract  agreement parties terms notice governing
OK  pred=contract true=contract  contrat termes conditions parties droit
ACCURACY 1.0000
INFER_VOCAB 31  TRAIN_VOCAB 31
```

Signs of the fix:

- Accuracy jumped from `0.33` to `1.00` - the model was fine all along; it was
  being fed the wrong features.
- `INFER_VOCAB` now equals `TRAIN_VOCAB` (both 31). Same vocabulary, same column
  order, same feature space at training and inference.

You caught a bug that never raised an error. That is the survive - and it is the
single most valuable NLP habit: reuse the exact same tokenizer/vectorizer at
inference that you fit at training.

---

## Verify

Run the scenario validator.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validator. It retrains, reruns your `check.py`, and confirms both
that the inference vocabulary matches the training vocabulary AND that accuracy
is high.

Expected output (yours will differ):

```
Running your check.py ...
...
ACCURACY 1.0000
INFER_VOCAB 31  TRAIN_VOCAB 31
PASS: tokenizer mismatch fixed (vocab matches at 31, accuracy 1.0000).
```

If you see `PASS`, you are done.

---

## Takeaways

- A tokenizer/feature mismatch is silent: no crash, no warning, just wrong
  answers and collapsed accuracy. It is one of the most dangerous NLP bugs.
- Fit the vectorizer ONCE at training, save it, and only ever `transform` with it
  afterward. Never `fit`/`fit_transform` at inference.
- A different vocabulary size at inference vs training (INFER_VOCAB != TRAIN_VOCAB)
  is a dead giveaway - always log and compare it.
- Clean and featurize text the SAME way at training and inference (Concepts 5.3).
  The model is only as good as the features it is fed.
- Suspiciously low accuracy with no errors should make you check the feature
  pipeline before you blame the model.

Prof. Happy (SUTA Labs)
