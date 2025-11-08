#!/bin/bash

# Automated PgBouncer Testing Script (No Manual Steps)
# Runs all benchmarks and displays results

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_header() {
    echo -e "${CYAN}"
    echo "════════════════════════════════════════════════════════"
    echo "  $1"
    echo "════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INVENTORY_FILE="$SCRIPT_DIR/ansible/inventory.ini"

# Get server IPs
MONITORING_IP=$(grep "monitoring-server ansible_host=" "$INVENTORY_FILE" | awk '{print $2}' | cut -d'=' -f2)
DB_IP=$(grep "db-server ansible_host=" "$INVENTORY_FILE" | awk '{print $2}' | cut -d'=' -f2)

print_header "Automated PgBouncer Benchmark Testing"

echo -e "${CYAN}Server Information:${NC}"
echo "  📊 Grafana:     http://${MONITORING_IP}:3000 (admin/admin)"
echo "  📈 Prometheus:  http://${MONITORING_IP}:9090"
echo "  🔌 PgBouncer:   ${DB_IP}:6432"
echo ""

# Step 1: Grant Permissions
print_header "Step 1: Setting Up Database Permissions"
print_info "Granting permissions to myuser..."

ssh -o StrictHostKeyChecking=no -i ~/.ssh/db-cluster.id_rsa \
    -J ubuntu@${MONITORING_IP} ubuntu@${DB_IP} << 'ENDSSH' 2>/dev/null
sudo -u postgres psql -d mydb << 'EOSQL'
GRANT ALL PRIVILEGES ON SCHEMA public TO myuser;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO myuser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO myuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO myuser;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO myuser;
EOSQL
ENDSSH

print_success "Permissions granted"

# Step 2: Initialize pgbench
print_header "Step 2: Initializing pgbench"
print_info "Creating pgbench tables..."

ssh -o StrictHostKeyChecking=no -i ~/.ssh/db-cluster.id_rsa \
    -J ubuntu@${MONITORING_IP} ubuntu@${DB_IP} << 'ENDSSH' 2>/dev/null
export PGPASSWORD='mypassword'
pgbench -h localhost -p 6432 -U myuser -i mydb
ENDSSH

print_success "pgbench initialized"

# Step 3: Run Basic Benchmark
print_header "Step 3: Basic Benchmark (10 clients, 100 transactions)"

ssh -o StrictHostKeyChecking=no -i ~/.ssh/db-cluster.id_rsa \
    -J ubuntu@${MONITORING_IP} ubuntu@${DB_IP} << 'ENDSSH'
export PGPASSWORD='mypassword'
pgbench -h localhost -p 6432 -U myuser -c 10 -j 2 -t 100 mydb
ENDSSH

print_success "Basic benchmark completed"

# Step 4: Run Load Test
print_header "Step 4: Load Test (50 clients, 1000 transactions)"

ssh -o StrictHostKeyChecking=no -i ~/.ssh/db-cluster.id_rsa \
    -J ubuntu@${MONITORING_IP} ubuntu@${DB_IP} << 'ENDSSH'
export PGPASSWORD='mypassword'
pgbench -h localhost -p 6432 -U myuser -c 50 -j 4 -t 1000 mydb
ENDSSH

print_success "Load test completed"

# Step 5: Custom SQL Test
print_header "Step 5: Custom SQL Workload"

ssh -o StrictHostKeyChecking=no -i ~/.ssh/db-cluster.id_rsa \
    -J ubuntu@${MONITORING_IP} ubuntu@${DB_IP} << 'ENDSSH'
cat > /tmp/test.sql << 'EOSQL'
BEGIN;
SELECT * FROM pgbench_accounts WHERE aid = :aid;
UPDATE pgbench_accounts SET abalance = abalance + 1 WHERE aid = :aid;
COMMIT;
EOSQL

export PGPASSWORD='mypassword'
pgbench -h localhost -p 6432 -U myuser -c 10 -j 2 -t 100 -f /tmp/test.sql mydb
rm /tmp/test.sql
ENDSSH

print_success "Custom SQL test completed"

# Step 6: PgBouncer Statistics
print_header "Step 6: PgBouncer Statistics"

ssh -o StrictHostKeyChecking=no -i ~/.ssh/db-cluster.id_rsa \
    -J ubuntu@${MONITORING_IP} ubuntu@${DB_IP} << 'ENDSSH'
export PGPASSWORD='mypassword'
echo ""
echo "=== PgBouncer Pool Stats ==="
psql -h localhost -p 6432 -U myuser -d pgbouncer -c "SHOW POOLS;" 2>/dev/null || true
echo ""
echo "=== PgBouncer Database Stats ==="
psql -h localhost -p 6432 -U myuser -d pgbouncer -c "SHOW STATS;" 2>/dev/null || true
ENDSSH

# Summary
print_header "Testing Complete! 🎉"
echo ""
echo -e "${GREEN}All benchmarks completed successfully!${NC}"
echo ""
echo -e "${CYAN}📊 View Real-Time Metrics:${NC}"
echo "  Grafana:    http://${MONITORING_IP}:3000"
echo "  Prometheus: http://${MONITORING_IP}:9090"
echo ""
echo -e "${YELLOW}📝 Grafana Setup (if not done):${NC}"
echo "  1. Login: admin/admin"
echo "  2. Add Prometheus data source: http://localhost:9090"
echo "  3. Import dashboards:"
echo "     - PostgreSQL: ID 9628"
echo "     - PgBouncer:  ID 13125"
echo ""
echo -e "${CYAN}🔑 Key Metrics to Monitor:${NC}"
echo "  • pgbouncer_pools_client_active_connections"
echo "  • pgbouncer_pools_server_active_connections"
echo "  • rate(pgbouncer_stats_queries_pooled_total[1m])"
echo "  • rate(pgbouncer_stats_sql_transactions_pooled_total[1m])"
echo ""
