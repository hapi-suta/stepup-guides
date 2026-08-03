#!/usr/bin/env bash
# Tier 7 SURVIVE scenario configuration
# Edit this file before running any inject.sh or validate.sh scripts.

# ============================================================
# REQUIRED - Fill these in before running any scenario
# ============================================================

# Your AWS region
export AWS_REGION="us-east-1"

# Source RDS instance identifier (the one with logical replication enabled)
export SOURCE_DB_IDENTIFIER="your-rds-source-instance"

# Target RDS instance identifier (subscriber / migration target)
export TARGET_DB_IDENTIFIER="your-rds-target-instance"

# Aurora cluster identifier (used for Serverless v2 and Lambda labs)
export AURORA_CLUSTER_IDENTIFIER="your-aurora-cluster"

# Source database endpoint (hostname only, no port)
export SOURCE_DB_HOST="your-source.xxxxxxxx.us-east-1.rds.amazonaws.com"

# Target database endpoint
export TARGET_DB_HOST="your-target.xxxxxxxx.us-east-1.rds.amazonaws.com"

# Database name used in the labs
export DB_NAME="replication_lab"

# Database master user
export DB_USER="postgres"

# S3 bucket name (used for import/export scenarios)
export S3_BUCKET="your-lab-bucket-name"

# SNS topic ARN for alerts (used by validate scripts to confirm alarm state)
export SNS_ALERT_TOPIC_ARN="arn:aws:sns:us-east-1:123456789012:rds-storage-alerts"

# ============================================================
# Optional overrides
# ============================================================

# PostgreSQL port (default 5432)
export DB_PORT="5432"

# DMS replication instance identifier (for scenario 02)
export DMS_REPLICATION_INSTANCE="tier7-dms-replication"

# DMS task ARN (for scenario 02 - fill in after creating the task)
export DMS_TASK_ARN=""

# Lambda function name (for scenario 03)
export LAMBDA_FUNCTION_NAME="order-status-notifier"

# ============================================================
# Derived values (do not edit)
# ============================================================

export PGPASSWORD="${PGPASSWORD:-}"  # Set via environment variable, not here
export SCENARIO_LOG_DIR="/tmp/tier7-survive-logs"

mkdir -p "${SCENARIO_LOG_DIR}"
