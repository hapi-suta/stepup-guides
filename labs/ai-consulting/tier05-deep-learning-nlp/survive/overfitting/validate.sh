#!/usr/bin/env bash
LAB="$HOME/tier5-overfit-lab"; cd "$LAB" 2>/dev/null || { echo "FAIL: lab dir missing"; exit 1; }
[ -f metrics.json ] || { echo "FAIL: no metrics.json - run train.py first"; exit 1; }
read -r V G < <(python3.12 -c "import json;m=json.load(open('metrics.json'));print(m['val_loss'],m['gap'])")
if python3.12 -c "import json;m=json.load(open('metrics.json'));import sys;sys.exit(0 if (m['val_loss']<0.65 and m['gap']<0.35) else 1)"; then
  echo "PASS: overfitting controlled (val_loss=$V, train/val gap=$G)"; exit 0
else
  echo "FAIL: overfitting - val_loss=$V, gap=$G too high. Add dropout + weight_decay and cut epochs (runbook)."; exit 1
fi
