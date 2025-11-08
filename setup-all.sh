#!/bin/bash

# Complete Automation Script for PgBouncer Infrastructure
# This script handles everything: SSH keys, infrastructure, inventory updates, and setup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

print_banner() {
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║   Complete PgBouncer Infrastructure Setup            ║
║   Automated: Keys → Infra → Config → Deploy          ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INFRA_DIR="$SCRIPT_DIR/infra"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"
KEY_NAME="db-cluster"
SSH_KEY_PATH="$HOME/.ssh/${KEY_NAME}.id_rsa"

print_banner

# Step 1: Check prerequisites
print_info "Step 1/5: Checking prerequisites..."

if ! command -v pulumi &> /dev/null; then
    print_error "Pulumi is not installed. Please install it first: https://www.pulumi.com/docs/get-started/install/"
fi

if ! command -v ansible &> /dev/null; then
    print_error "Ansible is not installed. Please install it: pip install ansible"
fi

if ! command -v ssh-keygen &> /dev/null; then
    print_error "ssh-keygen is not installed"
fi

print_success "All prerequisites are installed"

# Step 2: Generate SSH key pair if it doesn't exist
print_info "Step 2/5: Setting up SSH keys..."

# Remove old keys if they exist to avoid mismatch
if [ -f "$SSH_KEY_PATH" ]; then
    print_info "Removing old SSH keys to regenerate..."
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
fi

# Generate new SSH key pair
print_info "Generating new SSH key pair..."
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "${KEY_NAME}-key" > /dev/null 2>&1
chmod 600 "$SSH_KEY_PATH"
chmod 644 "${SSH_KEY_PATH}.pub"

print_success "SSH key pair generated at $SSH_KEY_PATH"

# Step 3: Deploy infrastructure with Pulumi
print_info "Step 3/5: Deploying AWS infrastructure with Pulumi..."

cd "$INFRA_DIR"

# Check if stack exists, if not select or create
if ! pulumi stack ls 2>/dev/null | grep -q "pg-dev1"; then
    print_info "Creating new Pulumi stack 'pg-dev1'..."
    pulumi stack init pg-dev1 || pulumi stack select pg-dev1
else
    pulumi stack select pg-dev1
fi

# Run pulumi up
print_info "Provisioning infrastructure (this may take 2-3 minutes)..."
pulumi up --yes

# Get outputs
print_info "Retrieving server IPs..."
MONITORING_PUBLIC_IP=$(pulumi stack output monitoring_server_public_ip)
DB_PRIVATE_IP=$(pulumi stack output postgres_db_private_ip)

if [ -z "$MONITORING_PUBLIC_IP" ] || [ -z "$DB_PRIVATE_IP" ]; then
    print_error "Failed to retrieve server IPs from Pulumi"
fi

print_success "Infrastructure deployed successfully"
echo "  Monitoring Server (Public): $MONITORING_PUBLIC_IP"
echo "  Database Server (Private):  $DB_PRIVATE_IP"

# Step 4: Update Ansible inventory automatically
print_info "Step 4/5: Updating Ansible inventory..."

INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"

cat > "$INVENTORY_FILE" << EOF
[db]
db-server ansible_host=$DB_PRIVATE_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/${KEY_NAME}.id_rsa ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyJump=ubuntu@$MONITORING_PUBLIC_IP'

[monitoring]
monitoring-server ansible_host=$MONITORING_PUBLIC_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/${KEY_NAME}.id_rsa ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

print_success "Ansible inventory updated"

# Step 5: Wait for instances to be ready and deploy software
print_info "Step 5/5: Waiting for EC2 instances to boot..."

# Wait for SSH to be available
print_info "Waiting for SSH connectivity (max 2 minutes)..."
for i in {1..24}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_PATH" "ubuntu@$MONITORING_PUBLIC_IP" "echo 'SSH OK'" > /dev/null 2>&1; then
        print_success "SSH connection successful"
        break
    fi
    if [ $i -eq 24 ]; then
        print_error "Cannot connect to monitoring server after 2 minutes. Please check security groups."
    fi
    echo -n "."
    sleep 5
done

# Wait for cloud-init to complete (apt locks)
print_info "Waiting for cloud-init to complete on all servers..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "ubuntu@$MONITORING_PUBLIC_IP" \
    "cloud-init status --wait" > /dev/null 2>&1 || true
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" -J "ubuntu@$MONITORING_PUBLIC_IP" "ubuntu@$DB_PRIVATE_IP" \
    "cloud-init status --wait" > /dev/null 2>&1 || true

print_success "Cloud-init completed on all servers"

# Run Ansible playbook
print_info "Running Ansible playbook to install PostgreSQL, PgBouncer, and monitoring..."
cd "$SCRIPT_DIR"

ansible-playbook ansible/playbooks/full-setup.yml

print_success "═══════════════════════════════════════════════════"
print_success "   SETUP COMPLETE! 🎉"
print_success "═══════════════════════════════════════════════════"
echo ""
echo -e "${BLUE}Access Points:${NC}"
echo "  📊 Grafana:    http://${MONITORING_PUBLIC_IP}:3000 (admin/admin)"
echo "  📈 Prometheus: http://${MONITORING_PUBLIC_IP}:9090"
echo "  🔌 PgBouncer:  ${DB_PRIVATE_IP}:6432"
echo "  🗄️  PostgreSQL: ${DB_PRIVATE_IP}:5432"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Run benchmarks: ansible-playbook ansible/playbooks/benchmark.yml"
echo "  2. Import Grafana dashboard from pgbouncer-dashboard.json"
echo "  3. Monitor metrics in real-time"
echo ""
echo -e "${BLUE}SSH Access:${NC}"
echo "  Monitoring: ssh -i ~/.ssh/${KEY_NAME}.id_rsa ubuntu@${MONITORING_PUBLIC_IP}"
echo "  Database:   ssh -i ~/.ssh/${KEY_NAME}.id_rsa -J ubuntu@${MONITORING_PUBLIC_IP} ubuntu@${DB_PRIVATE_IP}"
echo ""
