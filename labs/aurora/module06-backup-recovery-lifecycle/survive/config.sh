#!/usr/bin/env bash
# Module 06 - SURVIVE Config
# Source this file in all scenario scripts

# --- Student fills these in ---
export CLUSTER_ID="${CLUSTER_ID:-devops-lab-cluster}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
export DB_SUBNET_GROUP="${DB_SUBNET_GROUP:-your-subnet-group}"
export VPC_SG_ID="${VPC_SG_ID:-sg-xxxxxxxxxxxxxxxxx}"
export CLUSTER_HOST="${CLUSTER_HOST:-}"
export DB_USER="${DB_USER:-postgres}"
export DB_NAME="${DB_NAME:-postgres}"
# ---

# Scenario timing targets (minutes)
export RTO_TARGET_MINUTES=30

# Temp dir for scenario artifacts
export SURVIVE_TMP="/tmp/devops-lab-survive"
mkdir -p "$SURVIVE_TMP"
