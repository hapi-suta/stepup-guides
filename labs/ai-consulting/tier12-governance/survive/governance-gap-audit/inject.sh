#!/usr/bin/env bash
set -euo pipefail

# SUTA Labs - SURVIVE chaos scenario: governance-gap-audit
# Injects an AI system inventory in which a deployed, high-risk system has
# NO impact assessment and NO human-oversight plan - a governance gap.
# The student must audit the inventory, find the gap, and remediate it by
# producing the missing artifacts and closing the inventory entry.
#
# Run as ec2-user on CentOS Stream 9. Safe to re-run (idempotent-ish).

WORKDIR="${HOME}/survive-governance-gap"

echo "=== SURVIVE: governance-gap-audit - injecting scenario ==="
echo

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

# 1. Write an AI system inventory as a simple CSV. One row is a deployed,
#    high-risk system that is MISSING its impact assessment and oversight plan.
cat > "${WORKDIR}/ai_system_inventory.csv" <<'CSVEOF'
id,name,purpose,owner,vendor_or_inhouse,risk_class,status,impact_assessment,oversight_plan
AI-001,Meeting Summarizer,Summarize internal meetings,ops-lead,vendor,minimal,production,not-required,not-required
AI-002,Support Chatbot,Answer customer FAQs,support-lead,vendor,limited,production,IA-2026-02-11.md,oversight-AI-002.md
AI-003,Benefits Eligibility Assistant,Score citizen benefit eligibility,MISSING,in-house,high,production,MISSING,MISSING
AI-004,Doc Search,Internal document search,eng-lead,in-house,limited,pilot,IA-2026-05-01.md,oversight-AI-004.md
CSVEOF

# 2. Write an audit helper the student can run to see the gaps. It is a
#    read-only check; it does NOT fix anything.
cat > "${WORKDIR}/audit_inventory.py" <<'PYEOF'
"""
Governance-gap audit. Reads the AI system inventory and flags any system
that (a) is in production, (b) is above 'minimal' risk, and (c) is missing
an impact assessment, an owner, or a human-oversight plan.

Read-only: it reports gaps, it does not fix them.
"""
import csv
import sys

MISSING = {"", "MISSING", "missing", "none", "None"}

gaps = []
with open("ai_system_inventory.csv", newline="") as f:
    for row in csv.DictReader(f):
        if row["status"].strip().lower() != "production":
            continue
        if row["risk_class"].strip().lower() == "minimal":
            continue
        problems = []
        if row["owner"].strip() in MISSING:
            problems.append("no named owner")
        if row["impact_assessment"].strip() in MISSING:
            problems.append("no impact assessment")
        if row["oversight_plan"].strip() in MISSING:
            problems.append("no human-oversight plan")
        if problems:
            gaps.append((row["id"], row["name"], row["risk_class"], problems))

print("=== GOVERNANCE-GAP AUDIT ===")
if not gaps:
    print("No governance gaps found. All production systems above minimal risk")
    print("have an owner, an impact assessment, and a human-oversight plan.")
    sys.exit(0)

for sid, name, risk, problems in gaps:
    print(f"GAP: {sid} ({name}) [risk={risk}]")
    for p in problems:
        print(f"       - {p}")
print()
print(f"{len(gaps)} system(s) with governance gaps. Remediate before this passes.")
sys.exit(1)
PYEOF

echo "--- Inventory and audit tool written to ${WORKDIR} ---"
echo
echo "--- Running the audit so you can see the gap (no venv needed) ---"
python3 "${WORKDIR}/audit_inventory.py" || true

echo
echo "=== INJECTION COMPLETE ==="
echo
echo "A deployed HIGH-RISK system (AI-003 Benefits Eligibility Assistant) is"
echo "live with no impact assessment, no oversight plan, and no named owner."
echo "Your job: audit the inventory, remediate the gap by producing the missing"
echo "artifacts, and update the inventory. Then run validate.sh."
echo
echo "Working directory: ${WORKDIR}"
echo "Open the runbook and follow the 3 layers."
