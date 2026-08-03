#!/usr/bin/env bash
# SURVIVE Configuration - Module 05 HA, Replication and Failover
# Source this file before running any SURVIVE scenario

# -------------------------------------------------------
# Cluster Identifiers - Fill in your actual values
# -------------------------------------------------------
export AURORA_CLUSTER_ID="devops-lab-cluster"
export AURORA_GLOBAL_ID="devops-aurora-global"
export SERVERLESS_CLUSTER_ID="devops-serverless-cluster"

# -------------------------------------------------------
# Endpoints - Fill in your actual endpoints
# -------------------------------------------------------
export AURORA_WRITER_ENDPOINT="devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com"
export AURORA_READER_ENDPOINT="devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com"
export GLOBAL_PRIMARY_ENDPOINT="devops-global-primary.cluster-xxxx.us-east-1.rds.amazonaws.com"
export GLOBAL_SECONDARY_ENDPOINT="devops-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com"
export SERVERLESS_ENDPOINT="devops-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com"

# -------------------------------------------------------
# Database Credentials
# -------------------------------------------------------
export DB_USER="postgres"
export DB_NAME="postgres"
# Set PGPASSWORD in your environment or use .pgpass - do not hardcode here

# -------------------------------------------------------
# AWS Configuration
# -------------------------------------------------------
export AWS_PRIMARY_REGION="us-east-1"
export AWS_SECONDARY_REGION="us-west-2"

# -------------------------------------------------------
# Aurora Instance Names
# -------------------------------------------------------
export AURORA_WRITER_INSTANCE="devops-lab-writer"
export AURORA_READER_1="devops-lab-reader-1"
export AURORA_READER_2="devops-lab-reader-2"

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
