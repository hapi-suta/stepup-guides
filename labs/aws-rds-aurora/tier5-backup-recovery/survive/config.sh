#!/usr/bin/env bash
# SUTA Labs - Tier 5 SURVIVE Config
# Source this file in all scenario scripts

# ─── Student fills these in ───────────────────────────────────────────────────
export DB_INSTANCE="${DB_INSTANCE:-suta-t5-primary-hfa}"
export AURORA_CLUSTER="${AURORA_CLUSTER:-suta-t5-aurora-hfa}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export DB_SUBNET_GROUP="${DB_SUBNET_GROUP:-your-subnet-group}"
export VPC_SG_ID="${VPC_SG_ID:-sg-xxxxxxxxxxxxxxxxx}"
export DB_HOST="${DB_HOST:-}"             # Set or auto-populated by common.sh
export DB_USER="${DB_USER:-postgres}"
export DB_NAME="${DB_NAME:-postgres}"
# ──────────────────────────────────────────────────────────────────────────────

# Scenario timing targets (minutes)
export RTO_TARGET_MINUTES=30

# Temp dir for scenario artifacts
export SURVIVE_TMP="/tmp/suta-t5-survive"
mkdir -p "$SURVIVE_TMP"
