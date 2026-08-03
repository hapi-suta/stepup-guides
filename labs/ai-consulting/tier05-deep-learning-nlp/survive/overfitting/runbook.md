# SURVIVE runbook: overfitting (validation loss high while training loss ~0)

**On the lab server, as ec2-user.**

## 1. See the symptom

`validate.sh` fails. Look at the metrics:

```
cat ~/tier5-overfit-lab/metrics.json
```

Expected output (yours will differ):

```
{"train_loss": 0.0000, "val_loss": 5.70, "gap": 5.70}
```

Near-zero training loss with a large validation loss is textbook overfitting: the model memorized the 40 training rows (including their noise) instead of learning the signal.

## 2. The three fixes

- **Dropout** randomly zeroes neurons each step so the model cannot lean on one path.
- **Weight decay** (L2) penalizes large weights, keeping the model simpler.
- **Fewer epochs** stops training before it memorizes.

## 3. Retrain with regularization

Turn on dropout (0.5), weight decay (0.1), and far fewer epochs (80):

```
cd ~/tier5-overfit-lab
python3.12 train.py 0.5 0.1 80
```

Expected output (yours will differ):

```
train_loss=0.2648 val_loss=0.5222 gap=0.2574
```

Training loss is no longer near zero and the gap is small - the model is generalizing.

## 4. Prove it is fixed

```
bash validate.sh
```

Expected output (yours will differ):

```
PASS: overfitting controlled (val_loss=0.5222, train/val gap=0.2574)
```

Prof. Happy (SUTA Labs)
