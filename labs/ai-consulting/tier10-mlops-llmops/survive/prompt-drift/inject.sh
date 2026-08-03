#!/usr/bin/env bash
set -euo pipefail
# =============================================================================
# SURVIVE scenario: prompt-drift
# Tier 10 - MLOps and LLMOps (ai-consulting track)
#
# What this injects:
#   An LLM app with a golden set and a prompt regression test. Someone has
#   "improved" the prompt template by adding "Answer in one word only." That
#   edit silently breaks every golden case - the answers no longer contain the
#   required facts. This is prompt drift: quality drops because the PROMPT
#   changed, not the data.
#
# Student goal (see runbook.md):
#   Run the regression suite, watch it FAIL, identify the bad prompt template as
#   the cause, restore a good prompt so the golden set passes again, and
#   document the prompt-drift finding. Everything runs offline (mock LLM).
#
# Runs on: CentOS Stream 9, user ec2-user, python3.12. Fully self-contained.
# =============================================================================

WORKDIR="${HOME}/survive-prompt-drift"

echo "==> Creating working directory at ${WORKDIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

echo "==> Creating Python 3.12 virtual environment"
python3.12 -m venv .venv
# shellcheck disable=SC1091
source "${WORKDIR}/.venv/bin/activate"
python -m pip install --quiet --upgrade pip

echo "==> Writing llm_client.py (offline mock, obeys prompt instructions)"
cat > llm_client.py <<'PYEOF'
"""Offline LLM client with a deterministic mock.

The mock OBEYS common prompt instructions ("one word", "brief") by truncating,
so a badly worded prompt template actually degrades the answer. No network or
key needed. If LLM_API_KEY is set the real path would be used; here the mock is
enough to demonstrate prompt drift.
"""
import hashlib
import os


def _base_answer(prompt):
    p = prompt.lower()
    if "capital of france" in p:
        return "The capital of France is Paris."
    if "refund" in p and "policy" in p:
        return "Refunds are available within 30 days of purchase with a receipt."
    if "reset" in p and "password" in p:
        return "To reset your password, click 'Forgot password' on the login page."
    return "MOCK_RESPONSE[" + hashlib.sha256(prompt.encode()).hexdigest()[:8] + "]"


def _apply(prompt, answer):
    p = prompt.lower()
    if "one word" in p or "single word" in p:
        return answer.split()[0] if answer.split() else answer
    if "brief" in p or "one sentence" in p or "short" in p or "concise" in p:
        return " ".join(answer.split()[:4])
    return answer


def complete(prompt, system=""):
    if not os.environ.get("LLM_API_KEY", "").strip():
        return _apply(prompt, _base_answer(prompt))
    # Real path omitted for this scenario; mock is sufficient offline.
    return _apply(prompt, _base_answer(prompt))
PYEOF

echo "==> Writing golden.json (the golden set)"
cat > golden.json <<'PYEOF'
[
  {"prompt": "What is the capital of France?", "must_include": ["Paris"]},
  {"prompt": "What is the refund policy?", "must_include": ["30 days", "receipt"]},
  {"prompt": "How do I reset my password?", "must_include": ["Forgot password", "login"]}
]
PYEOF

echo "==> Writing prompt_regression.py (the regression gate)"
cat > prompt_regression.py <<'PYEOF'
"""Prompt regression test against the golden set. Exit 1 if any case fails."""
import json
import sys
from pathlib import Path

from llm_client import complete


def load_template():
    p = Path("prompt_template.txt")
    return p.read_text() if p.exists() else "{question}"


def main():
    template = load_template()
    golden = json.loads(Path("golden.json").read_text())
    failures = 0
    for case in golden:
        prompt = template.replace("{question}", case["prompt"])
        answer = complete(prompt)
        missing = [s for s in case["must_include"] if s.lower() not in answer.lower()]
        if missing:
            failures += 1
            print(f"FAIL: {case['prompt']!r}")
            print(f"      missing: {missing}")
            print(f"      got: {answer!r}")
        else:
            print(f"PASS: {case['prompt']!r}")
    print("")
    if failures:
        print(f"RESULT: FAIL - {failures} of {len(golden)} golden cases failed")
        return 1
    print(f"RESULT: PASS - all {len(golden)} golden cases passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF

echo "==> Injecting prompt drift: a 'one word only' template that breaks the golden set"
# This is the drift - a prompt edit that silently ruins answer quality.
printf 'Answer in one word only. %s' '{question}' > prompt_template.txt

echo "==> Running the regression suite so you can see the drift"
echo "-----------------------------------------------------------------"
python prompt_regression.py || true
echo "-----------------------------------------------------------------"

cat <<EOF

==> Injection complete.

Someone edited the prompt template to force one-word answers. Every golden case
now FAILS because the answers no longer contain the required facts. This is
prompt drift: quality dropped because the PROMPT changed, not the data.

Working directory: ${WORKDIR}
Files:
  llm_client.py         - offline mock LLM; do not edit
  golden.json           - the golden set; do not edit
  prompt_regression.py  - the regression gate; do not edit
  prompt_template.txt   - the DRIFTED prompt (this is the problem)

Now follow runbook.md to identify the bad prompt, restore a good one so the
golden set passes, and document the finding.
Reference: Concepts 10.5 (prompt drift) and 10.4 (prompt regression testing).
EOF
