#!/usr/bin/env bash
# =============================================================================
# Voleon DBA Lab - Provision Fresh Environment
# =============================================================================
# Creates 4 clean CentOS Stream 9 servers ready for BUILD guides.
#
# Pre-configured on each node:
#   - Hostname (pg-sutalabs-1 through pg-sutalabs-4)
#   - /etc/hosts with all 4 nodes
#   - Inter-node SSH (root-to-root and ec2-user-to-ec2-user)
#   - postgres OS user
#   - /opt/pgsql/{data,wal,log,backup} directories
#
# Nothing else installed - student builds everything from BUILD 01.
#
# Usage:
#   ./scripts/provision-lab.sh                    # provision new servers
#   ./scripts/provision-lab.sh --terminate-only   # just terminate existing
#
# Prerequisites:
#   - AWS CLI configured with HA001 account credentials
#   - voleon-lab SSH key pair exists in us-east-1
#   - ~/.ssh/id_ed25519 exists locally
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${LAB_DIR}/config.sh"

# ---- AWS Settings ----------------------------------------------------------
AWS_REGION="us-east-1"
AMI_OWNER="125523088429"        # CentOS official
AMI_FILTER="CentOS Stream 9*"
KEY_NAME="voleon-lab"
SG_ID="sg-029a684edd2cec982"
SUBNET_ID="subnet-07538e84ecf825ba7"
SSH_KEY="$HOME/.ssh/id_ed25519"

# ---- Node Definitions ------------------------------------------------------
declare -a NODE_NAMES=("pg-sutalabs-1" "pg-sutalabs-2" "pg-sutalabs-3" "pg-sutalabs-4")
declare -a NODE_ROLES=("primary" "replica" "container" "ops")
declare -a NODE_TYPES=("t3.medium" "t3.medium" "t3.medium" "t3.small")
declare -a NODE_TAGS=("voleon-lab-pg-primary" "voleon-lab-pg-replica" "voleon-lab-pg-container" "voleon-lab-pg-ops")
DISK_SIZE=30
DISK_TYPE="gp3"

# ---- Helpers ---------------------------------------------------------------
log()  { echo -e "\033[0;36m[INFO]\033[0m  $(date +%H:%M:%S) $*"; }
ok()   { echo -e "\033[0;32m[OK]\033[0m    $(date +%H:%M:%S) $*"; }
err()  { echo -e "\033[0;31m[ERROR]\033[0m $(date +%H:%M:%S) $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $(date +%H:%M:%S) $*"; }

ssh_node() {
    local ip=$1; shift
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -i "$SSH_KEY" ec2-user@"$ip" "$@" 2>/dev/null
}

# ---- Step 1: Terminate existing instances ----------------------------------
terminate_existing() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        warn "No config.sh found - skipping termination"
        return
    fi

    source "$CONFIG_FILE"
    if [[ -z "${AWS_INSTANCE_IDS:-}" ]]; then
        warn "No AWS_INSTANCE_IDS in config.sh - skipping termination"
        return
    fi

    log "Terminating existing instances: $AWS_INSTANCE_IDS"
    aws ec2 terminate-instances \
        --instance-ids $AWS_INSTANCE_IDS \
        --region "$AWS_REGION" \
        --query 'TerminatingInstances[].[InstanceId,CurrentState.Name]' \
        --output table 2>&1 || warn "Some instances may already be terminated"

    log "Waiting for termination..."
    aws ec2 wait instance-terminated \
        --instance-ids $AWS_INSTANCE_IDS \
        --region "$AWS_REGION" 2>/dev/null || true
    ok "Old instances terminated"
}

# ---- Step 2: Find latest CentOS Stream 9 AMI ------------------------------
find_ami() {
    log "Finding latest CentOS Stream 9 AMI..."
    AMI_ID=$(aws ec2 describe-images \
        --owners "$AMI_OWNER" \
        --filters "Name=name,Values=${AMI_FILTER}" "Name=architecture,Values=x86_64" "Name=state,Values=available" \
        --region "$AWS_REGION" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

    if [[ -z "$AMI_ID" || "$AMI_ID" == "None" ]]; then
        err "Could not find CentOS Stream 9 AMI"
        exit 1
    fi
    ok "AMI: $AMI_ID"
}

# ---- Step 3: Launch instances ----------------------------------------------
launch_instances() {
    log "Launching 4 instances..."
    declare -g -a INSTANCE_IDS=()

    for i in 0 1 2 3; do
        local tag="${NODE_TAGS[$i]}"
        local type="${NODE_TYPES[$i]}"

        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --instance-type "$type" \
            --key-name "$KEY_NAME" \
            --security-group-ids "$SG_ID" \
            --subnet-id "$SUBNET_ID" \
            --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":${DISK_SIZE},\"VolumeType\":\"${DISK_TYPE}\"}}]" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${tag}}]" \
            --region "$AWS_REGION" \
            --query 'Instances[0].InstanceId' --output text)

        INSTANCE_IDS+=("$INSTANCE_ID")
        ok "Launched $tag: $INSTANCE_ID ($type)"
    done

    log "Waiting for all instances to be running..."
    aws ec2 wait instance-running \
        --instance-ids "${INSTANCE_IDS[@]}" \
        --region "$AWS_REGION"
    ok "All instances running"
}

# ---- Step 4: Collect IPs --------------------------------------------------
collect_ips() {
    log "Collecting IP addresses..."
    declare -g -a PUBLIC_IPS=()
    declare -g -a PRIVATE_IPS=()

    for id in "${INSTANCE_IDS[@]}"; do
        local info
        info=$(aws ec2 describe-instances \
            --instance-ids "$id" \
            --region "$AWS_REGION" \
            --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' --output text)
        local pub_ip priv_ip
        pub_ip=$(echo "$info" | awk '{print $1}')
        priv_ip=$(echo "$info" | awk '{print $2}')
        PUBLIC_IPS+=("$pub_ip")
        PRIVATE_IPS+=("$priv_ip")
        ok "${NODE_NAMES[${#PUBLIC_IPS[@]}-1]}: public=$pub_ip private=$priv_ip"
    done
}

# ---- Step 5: Wait for SSH -------------------------------------------------
wait_for_ssh() {
    log "Waiting for SSH on all nodes..."
    for ip in "${PUBLIC_IPS[@]}"; do
        for attempt in $(seq 1 30); do
            if ssh_node "$ip" "echo ok" >/dev/null 2>&1; then
                break
            fi
            sleep 2
        done
    done
    ok "SSH ready on all nodes"
}

# ---- Step 6: Configure nodes ----------------------------------------------
configure_nodes() {
    log "Configuring nodes..."

    # Build /etc/hosts block
    local hosts_block=""
    for i in 0 1 2 3; do
        hosts_block+="${PRIVATE_IPS[$i]} ${NODE_NAMES[$i]}"$'\n'
    done

    # Configure each node
    for i in 0 1 2 3; do
        local hostname="${NODE_NAMES[$i]}"
        local ip="${PUBLIC_IPS[$i]}"

        log "Configuring $hostname ($ip)..."
        ssh_node "$ip" "
            sudo hostnamectl set-hostname $hostname
            echo '$hosts_block' | sudo tee -a /etc/hosts > /dev/null
            sudo useradd -m -s /bin/bash postgres 2>/dev/null || true
            sudo mkdir -p /opt/pgsql/{data,wal,log,backup}
            sudo chown -R postgres:postgres /opt/pgsql
        "
        ok "$hostname configured"
    done
}

# ---- Step 7: Setup inter-node SSH -----------------------------------------
setup_ssh() {
    log "Setting up inter-node SSH..."

    # Generate key on node 1
    ssh_node "${PUBLIC_IPS[0]}" "sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N '' -q 2>/dev/null || true"
    local root_pubkey root_privkey
    root_pubkey=$(ssh_node "${PUBLIC_IPS[0]}" "sudo cat /root/.ssh/id_ed25519.pub")
    root_privkey=$(ssh_node "${PUBLIC_IPS[0]}" "sudo cat /root/.ssh/id_ed25519")

    # Generate ec2-user key on node 1
    ssh_node "${PUBLIC_IPS[0]}" "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -q 2>/dev/null || true"
    local ec2_pubkey ec2_privkey
    ec2_pubkey=$(ssh_node "${PUBLIC_IPS[0]}" "cat ~/.ssh/id_ed25519.pub")
    ec2_privkey=$(ssh_node "${PUBLIC_IPS[0]}" "cat ~/.ssh/id_ed25519")

    local all_hosts="${NODE_NAMES[*]}"

    for ip in "${PUBLIC_IPS[@]}"; do
        # Root SSH
        ssh_node "$ip" "
            sudo mkdir -p /root/.ssh
            echo '$root_pubkey' | sudo tee -a /root/.ssh/authorized_keys > /dev/null
            sudo chmod 700 /root/.ssh
            sudo chmod 600 /root/.ssh/authorized_keys
            echo '$root_privkey' | sudo tee /root/.ssh/id_ed25519 > /dev/null
            sudo chmod 600 /root/.ssh/id_ed25519
            sudo ssh-keyscan -H $all_hosts 2>/dev/null | sudo tee -a /root/.ssh/known_hosts > /dev/null
        "

        # ec2-user SSH
        ssh_node "$ip" "
            echo '$ec2_pubkey' >> ~/.ssh/authorized_keys
            echo '$ec2_privkey' > ~/.ssh/id_ed25519
            chmod 600 ~/.ssh/id_ed25519
            ssh-keyscan -H $all_hosts 2>/dev/null >> ~/.ssh/known_hosts
        "
    done

    # Verify
    local test_result
    test_result=$(ssh_node "${PUBLIC_IPS[0]}" "ssh -o StrictHostKeyChecking=no ${NODE_NAMES[1]} hostname" 2>/dev/null)
    if [[ "$test_result" == "${NODE_NAMES[1]}" ]]; then
        ok "Inter-node SSH working (${NODE_NAMES[0]} -> ${NODE_NAMES[1]})"
    else
        warn "Inter-node SSH test returned: $test_result"
    fi
}

# ---- Step 8: Update config.sh ---------------------------------------------
update_config() {
    log "Updating config.sh..."

    local instance_ids_str="${INSTANCE_IDS[*]}"

    # Update public IPs
    sed -i.bak \
        -e "s|^PRIMARY_HOST=.*|PRIMARY_HOST=\"${PUBLIC_IPS[0]}\"|" \
        -e "s|^REPLICA_HOST=.*|REPLICA_HOST=\"${PUBLIC_IPS[1]}\"|" \
        -e "s|^CONTAINER_HOST=.*|CONTAINER_HOST=\"${PUBLIC_IPS[2]}\"|" \
        -e "s|^OPS_HOST=.*|OPS_HOST=\"${PUBLIC_IPS[3]}\"|" \
        -e "s|^PRIMARY_PRIVATE=.*|PRIMARY_PRIVATE=\"${PRIVATE_IPS[0]}\"|" \
        -e "s|^REPLICA_PRIVATE=.*|REPLICA_PRIVATE=\"${PRIVATE_IPS[1]}\"|" \
        -e "s|^CONTAINER_PRIVATE=.*|CONTAINER_PRIVATE=\"${PRIVATE_IPS[2]}\"|" \
        -e "s|^OPS_PRIVATE=.*|OPS_PRIVATE=\"${PRIVATE_IPS[3]}\"|" \
        -e "s|^AWS_INSTANCE_IDS=.*|AWS_INSTANCE_IDS=\"${instance_ids_str}\"|" \
        "$CONFIG_FILE"

    rm -f "${CONFIG_FILE}.bak"
    ok "config.sh updated with new IPs"
}

# ---- Step 9: Sync to control plane ----------------------------------------
sync_control_plane() {
    local SUTA_KEY="$HOME/Projects/jd/suta-openclaw.pem"
    local SUTA_HOST="ec2-user@32.199.6.222"
    local REMOTE_DIR="~/.openclaw/workspace/data/labs-repo/postgres/projects/voleon-dba-lab"

    if [[ ! -f "$SUTA_KEY" ]]; then
        warn "Control plane key not found at $SUTA_KEY - skipping sync"
        return
    fi

    log "Syncing to control plane..."
    rsync -avz -e "ssh -4 -i $SUTA_KEY" \
        "${LAB_DIR}/config.sh" \
        "${SUTA_HOST}:${REMOTE_DIR}/config.sh" >/dev/null 2>&1
    ok "Control plane synced"
}

# ---- Main ------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Voleon DBA Lab - Environment Provisioning"
    echo "=============================================="
    echo ""

    if [[ "${1:-}" == "--terminate-only" ]]; then
        terminate_existing
        echo ""
        ok "Instances terminated. Run without --terminate-only to provision new ones."
        exit 0
    fi

    terminate_existing
    echo ""
    find_ami
    launch_instances
    collect_ips
    wait_for_ssh
    configure_nodes
    setup_ssh
    update_config
    sync_control_plane

    echo ""
    echo "=============================================="
    echo " Lab Environment Ready"
    echo "=============================================="
    echo ""
    echo "  ${NODE_NAMES[0]} (${NODE_ROLES[0]}):    ${PUBLIC_IPS[0]}  ${NODE_TYPES[0]}"
    echo "  ${NODE_NAMES[1]} (${NODE_ROLES[1]}):    ${PUBLIC_IPS[1]}  ${NODE_TYPES[1]}"
    echo "  ${NODE_NAMES[2]} (${NODE_ROLES[2]}):  ${PUBLIC_IPS[2]}  ${NODE_TYPES[2]}"
    echo "  ${NODE_NAMES[3]} (${NODE_ROLES[3]}):       ${PUBLIC_IPS[3]}  ${NODE_TYPES[3]}"
    echo ""
    echo "  SSH: ssh ec2-user@${PUBLIC_IPS[0]}"
    echo ""
    echo "  Clean CentOS Stream 9 - ready for BUILD 01."
    echo "=============================================="
}

main "$@"
