#!/usr/bin/env bash
# SURVIVE Configuration - Tier 4 Availability
# Source this file before running any SURVIVE scenario

# -------------------------------------------------------
# Cluster Identifiers - Fill in your actual values
# -------------------------------------------------------
export RDS_INSTANCE_ID="my-postgres"
export AURORA_CLUSTER_ID="my-aurora-cluster"
export AURORA_GLOBAL_ID="my-aurora-global"
export SERVERLESS_CLUSTER_ID="my-serverless-cluster"

# -------------------------------------------------------
# Endpoints - Fill in your actual endpoints
# -------------------------------------------------------
export RDS_ENDPOINT="my-postgres.xxxx.us-east-1.rds.amazonaws.com"
export AURORA_WRITER_ENDPOINT="my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com"
export AURORA_READER_ENDPOINT="my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com"
export AURORA_SECONDARY_ENDPOINT="my-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com"
export SERVERLESS_ENDPOINT="my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com"

# -------------------------------------------------------
# Database Credentials
# -------------------------------------------------------
export DB_USER="postgres"
export DB_NAME="postgres"
# Set PGPASSWORD in your environment or use .pgpass - do not hardcode here
# export PGPASSWORD="YourPassword"

# -------------------------------------------------------
# AWS Configuration
# -------------------------------------------------------
export AWS_PRIMARY_REGION="us-east-1"
export AWS_SECONDARY_REGION="us-west-2"

# -------------------------------------------------------
# Aurora Instance Names
# -------------------------------------------------------
export AURORA_WRITER_INSTANCE="my-aurora-writer"
export AURORA_READER_1="my-aurora-reader-1"
export AURORA_READER_2="my-aurora-reader-2"

# -------------------------------------------------------
# Survive Lab Settings
# -------------------------------------------------------
export SURVIVE_LOG_DIR="/tmp/survive-logs"
export SURVIVE_RESULTS_DIR="/tmp/survive-results"

mkdir -p "$SURVIVE_LOG_DIR"
mkdir -p "$SURVIVE_RESULTS_DIR"

echo "Survive config loaded."
echo "Primary Region : $AWS_PRIMARY_REGION"
echo "Secondary Region: $AWS_SECONDARY_REGION"
echo "Aurora Cluster : $AURORA_CLUSTER_ID"
