#!/bin/bash
# =============================================================================
# Module 09: Operations at Scale and SRE - SURVIVE Configuration
# =============================================================================
# This file contains environment variables shared across all SURVIVE scenarios.
# Source this file at the top of every inject.sh and validate.sh script.
#
# Usage: source "$(dirname "$0")/../config.sh"
# =============================================================================

# Aurora Cluster Configuration
export M09_CLUSTER_ID="${M09_CLUSTER_ID:-devops-lab-cluster}"
export M09_INSTANCE_ID="${M09_INSTANCE_ID:-devops-lab-cluster-instance-1}"
export M09_READER_ID="${M09_READER_ID:-devops-lab-cluster-instance-2}"
export M09_REGION="${M09_REGION:-us-east-1}"

# Database Connection
export M09_DB_HOST="${M09_DB_HOST:-devops-lab-cluster.cluster-xxxxxxxxxxxx.us-east-1.rds.amazonaws.com}"
export M09_DB_PORT="${M09_DB_PORT:-5432}"
export M09_DB_USER="${M09_DB_USER:-postgres}"
export M09_DB_NAME="${M09_DB_NAME:-postgres}"

# Parameter Groups
export M09_CLUSTER_PARAM_GROUP="${M09_CLUSTER_PARAM_GROUP:-devops-lab-cluster-params}"
export M09_INSTANCE_PARAM_GROUP="${M09_INSTANCE_PARAM_GROUP:-devops-lab-instance-params}"

# Tags
export M09_ENVIRONMENT="${M09_ENVIRONMENT:-lab}"
export M09_COST_CENTER="${M09_COST_CENTER:-CC-LAB}"
export M09_TEAM="${M09_TEAM:-dba-training}"

# Chaos Resources (created by inject scripts, cleaned up by validate scripts)
export M09_CHAOS_PREFIX="m09-chaos"

# State directory (inject scripts save state here for validate scripts)
export M09_STATE_DIR="/tmp/m09-survive-state"
mkdir -p "${M09_STATE_DIR}"
