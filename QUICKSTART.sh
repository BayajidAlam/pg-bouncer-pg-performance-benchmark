#!/bin/bash

# PgBouncer Infrastructure Quick Start Script
# This script automates the complete setup of PostgreSQL, PgBouncer, Prometheus, and Grafana

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to print banner
print_banner() {
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║   PgBouncer Infrastructure Automation                ║
║   PostgreSQL + PgBouncer + Prometheus + Grafana      ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed. Please install Ansible first."
        echo "Install with: sudo apt update && sudo apt install ansible -y"
        exit 1
    fi
    
    print_success "Ansible is installed: $(ansible --version | head -n 1)"
    
    # Check if inventory file exists
    if [ ! -f "ansible/inventory.ini" ]; then
        print_error "Inventory file not found at ansible/inventory.ini"
        exit 1
    fi
    
    print_success "Inventory file found"
    
    # Check SSH key
    if [ ! -f "$HOME/.ssh/db-cluster.id_rsa" ]; then
        print_warning "SSH key not found at ~/.ssh/db-cluster.id_rsa"
        print_info "Make sure your SSH key is properly configured"
    else
        print_success "SSH key found"
    fi
}

# Test connectivity
test_connectivity() {
    print_info "Testing connectivity to servers..."
    
    if ansible all -i ansible/inventory.ini -m ping > /dev/null 2>&1; then
        print_success "Successfully connected to all servers"
    else
        print_error "Failed to connect to servers. Please check:"
        echo "  1. Server IPs in ansible/inventory.ini"
        echo "  2. SSH key permissions: chmod 400 ~/.ssh/db-cluster.id_rsa"
        echo "  3. Security group rules allow SSH access"
        exit 1
    fi
}

# Display configuration
display_config() {
    print_info "Current Configuration:"
    echo ""
    echo "Database Server:"
    grep "^\[db\]" -A 1 ansible/inventory.ini | tail -n 1 | awk '{print "  Host: " $2}' | sed 's/ansible_host=//'
    echo ""
    echo "Monitoring Server:"
    grep "^\[monitoring\]" -A 1 ansible/inventory.ini | tail -n 1 | awk '{print "  Host: " $2}' | sed 's/ansible_host=//'
    echo ""
}

# Run setup
run_setup() {
    print_info "Starting complete infrastructure setup..."
    echo ""
    
    print_info "This will setup:"
    echo "  ✓ PostgreSQL database server"
    echo "  ✓ PgBouncer connection pooler"
    echo "  ✓ Prometheus exporters"
    echo "  ✓ Prometheus monitoring"
    echo "  ✓ Grafana dashboards"
    echo ""
    
    read -p "Do you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        print_warning "Setup cancelled by user"
        exit 0
    fi
    
    print_info "Running Ansible playbook..."
    echo ""
    
    if ansible-playbook -i ansible/inventory.ini ansible/playbooks/full-setup.yml; then
        print_success "Setup completed successfully!"
    else
        print_error "Setup failed. Please check the error messages above."
        exit 1
    fi
}

# Display access information
display_access_info() {
    echo ""
    print_success "═══════════════════════════════════════════════════"
    print_success "           Setup Complete!"
    print_success "═══════════════════════════════════════════════════"
    echo ""
    
    # Extract IPs from inventory
    DB_IP=$(grep "^\[db\]" -A 1 ansible/inventory.ini | tail -n 1 | grep -oP 'ansible_host=\K[0-9.]+')
    MON_IP=$(grep "^\[monitoring\]" -A 1 ansible/inventory.ini | tail -n 1 | grep -oP 'ansible_host=\K[0-9.]+')
    
    echo "🗄️  Database Server (Private IP: $DB_IP)"
    echo "   └─ PostgreSQL:          Port 5432"
    echo "   └─ PgBouncer:           Port 6432"
    echo "   └─ PostgreSQL Exporter: Port 9187"
    echo "   └─ PgBouncer Exporter:  Port 9127"
    echo ""
    
    echo "📊 Monitoring Server (Public IP: $MON_IP)"
    echo "   └─ Prometheus: http://$MON_IP:9090"
    echo "   └─ Grafana:    http://$MON_IP:3000"
    echo "      Username: admin"
    echo "      Password: admin"
    echo ""
    
    echo "🔗 Next Steps:"
    echo "   1. Access Grafana dashboard at http://$MON_IP:3000"
    echo "   2. Add Prometheus data source (URL: http://prometheus:9090)"
    echo "   3. Import PostgreSQL dashboard (ID: 9628)"
    echo "   4. Import PgBouncer dashboard (ID: 13125)"
    echo "   5. Run benchmark tests:"
    echo "      ssh db-server"
    echo "      pgbench -h localhost -p 6432 -U myuser -i mydb"
    echo "      pgbench -h localhost -p 6432 -U myuser -c 10 -j 2 -t 100 mydb"
    echo ""
    
    print_success "═══════════════════════════════════════════════════"
}

# Main execution
main() {
    clear
    print_banner
    
    check_prerequisites
    echo ""
    
    display_config
    echo ""
    
    test_connectivity
    echo ""
    
    run_setup
    
    display_access_info
}

# Run main function
main
