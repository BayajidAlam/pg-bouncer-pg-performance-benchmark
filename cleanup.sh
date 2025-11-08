#!/bin/bash

# Cleanup Script - Destroys all AWS infrastructure
# Use this to tear down everything and start fresh

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${YELLOW}"
cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║   ⚠️  INFRASTRUCTURE CLEANUP                          ║
║   This will DELETE all AWS resources                 ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INFRA_DIR="$SCRIPT_DIR/infra"

echo -e "${YELLOW}Warning: This will destroy:${NC}"
echo "  - EC2 instances (monitoring & database servers)"
echo "  - VPC, subnets, and networking"
echo "  - NAT Gateway and Elastic IP"
echo "  - Security groups"
echo "  - SSH key pair in AWS (local key will be kept)"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${GREEN}Cleanup cancelled.${NC}"
    exit 0
fi

cd "$INFRA_DIR"

echo -e "${YELLOW}[INFO]${NC} Destroying infrastructure..."
pulumi destroy --yes

echo -e "${GREEN}[SUCCESS]${NC} All AWS resources have been destroyed."
echo ""
echo -e "${YELLOW}Note:${NC} Local SSH keys at ~/.ssh/db-cluster.id_rsa are preserved."
echo "To remove them: rm ~/.ssh/db-cluster.id_rsa*"
echo ""
echo "To recreate everything, run: ./setup-all.sh"
