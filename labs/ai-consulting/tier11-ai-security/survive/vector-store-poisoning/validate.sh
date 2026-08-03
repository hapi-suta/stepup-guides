#!/usr/bin/env bash
# SURVIVE validate: prove the poisoned records are quarantined and the store is
# clean, while the good records remain.
#
# PASS conditions:
#   1. A password question no longer returns the phishing URL.
#   2. The poisoned records (from 'anonymous') are gone from knowledge.json.
#   3. The good records are still present (nothing over-deleted).
#   4. The quarantined records were preserved for review (quarantine.json), not
#      silently destroyed.
#
# Run as ec2-user after following runbook.md.
set -uo pipefail

LAB="${LAB:-$HOME/t11-vector-poison}"
cd "$LAB" 2>/dev/null || { echo "FAIL: $LAB not found - run inject.sh first"; exit 1; }

fail() { echo "FAIL: $1"; exit 1; }

# 1. Password question must not return the phishing URL.
OUT="$(python3 query.py 'how do I reset my password' 2>/dev/null || true)"
echo "INFO: password query returned:"
echo "$OUT"
if echo "$OUT" | grep -qi "example.ru"; then
  fail "the phishing URL is still returned - store not cleaned"
fi
echo "OK: phishing record no longer returned"

# 2. Poisoned records gone from the live store.
if grep -qi "example.ru" knowledge.json; then
  fail "phishing record still in knowledge.json"
fi
if grep -qi "unlimited amounts with no receipts" knowledge.json; then
  fail "false-policy record still in knowledge.json"
fi
if grep -q "anonymous" knowledge.json; then
  fail "records from 'anonymous' are still in the live store"
fi
echo "OK: poisoned records removed from the live store"

# 3. Good records still present.
for keep in "kb-1" "kb-2" "kb-3"; do
  grep -q "\"$keep\"" knowledge.json || fail "good record $keep was deleted - over-cleaned"
done
echo "OK: good records preserved"

# 4. Quarantine kept the removed records for review.
[ -f quarantine.json ] || fail "quarantine.json not found - poison should be quarantined, not destroyed"
if ! grep -qi "example.ru" quarantine.json; then
  fail "quarantine.json does not contain the removed phishing record"
fi
echo "OK: poisoned records quarantined for review"

echo "PASS: vector store poisoning detected, quarantined, and cleaned."
