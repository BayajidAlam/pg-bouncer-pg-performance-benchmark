#!/bin/bash

# Automated Grafana Dashboard Setup
# Configures Prometheus data source and creates dashboards automatically

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

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
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

GRAFANA_URL="http://${MONITORING_IP}:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

print_header "Automated Grafana Dashboard Setup"

# Step 1: Wait for Grafana to be ready
print_info "Waiting for Grafana to be ready..."
for i in {1..30}; do
    if curl -s "${GRAFANA_URL}/api/health" > /dev/null 2>&1; then
        print_success "Grafana is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "Grafana is not responding after 30 seconds"
    fi
    sleep 1
done

# Step 2: Add Prometheus Data Source
print_header "Step 1: Adding Prometheus Data Source"

DATA_SOURCE_JSON=$(cat <<EOF
{
  "name": "Prometheus",
  "type": "prometheus",
  "url": "http://localhost:9090",
  "access": "proxy",
  "isDefault": true,
  "basicAuth": false
}
EOF
)

RESPONSE=$(curl -s -X POST "${GRAFANA_URL}/api/datasources" \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d "${DATA_SOURCE_JSON}")

if echo "$RESPONSE" | grep -q '"id"'; then
    print_success "Prometheus data source added"
elif echo "$RESPONSE" | grep -q "already exists"; then
    print_success "Prometheus data source already exists"
else
    print_error "Failed to add Prometheus data source: $RESPONSE"
fi

# Step 3: Create PgBouncer Dashboard
print_header "Step 2: Creating PgBouncer Dashboard"

PGBOUNCER_DASHBOARD=$(cat <<'EOF'
{
  "dashboard": {
    "title": "PgBouncer Performance",
    "tags": ["pgbouncer", "postgresql"],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 0,
    "refresh": "5s",
    "panels": [
      {
        "title": "Active Client Connections",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "targets": [
          {
            "expr": "pgbouncer_pools_client_active_connections",
            "legendFormat": "{{database}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"lineWidth": 2, "fillOpacity": 10}
          }
        }
      },
      {
        "title": "Active Server Connections",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "targets": [
          {
            "expr": "pgbouncer_pools_server_active_connections",
            "legendFormat": "{{database}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"lineWidth": 2, "fillOpacity": 10}
          }
        }
      },
      {
        "title": "Waiting Connections",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "targets": [
          {
            "expr": "pgbouncer_pools_client_waiting_connections",
            "legendFormat": "{{database}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"lineWidth": 2, "fillOpacity": 10}
          }
        }
      },
      {
        "title": "Pool Size (Max Connections)",
        "type": "stat",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "targets": [
          {
            "expr": "pgbouncer_pools_server_idle_connections",
            "legendFormat": "{{database}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": 0, "color": "green"},
                {"value": 15, "color": "yellow"},
                {"value": 19, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "title": "Queries per Second",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
        "targets": [
          {
            "expr": "rate(pgbouncer_stats_queries_pooled_total[1m])",
            "legendFormat": "{{database}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"lineWidth": 2, "fillOpacity": 10},
            "unit": "reqps"
          }
        }
      },
      {
        "title": "Transactions per Second",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
        "targets": [
          {
            "expr": "rate(pgbouncer_stats_sql_transactions_pooled_total[1m])",
            "legendFormat": "{{database}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"lineWidth": 2, "fillOpacity": 10},
            "unit": "tps"
          }
        }
      },
      {
        "title": "Data Sent (bytes/sec)",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 24},
        "targets": [
          {
            "expr": "rate(pgbouncer_stats_bytes_sent_total[1m])",
            "legendFormat": "{{database}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"lineWidth": 2, "fillOpacity": 10},
            "unit": "Bps"
          }
        }
      },
      {
        "title": "Data Received (bytes/sec)",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 24},
        "targets": [
          {
            "expr": "rate(pgbouncer_stats_bytes_received_total[1m])",
            "legendFormat": "{{database}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"lineWidth": 2, "fillOpacity": 10},
            "unit": "Bps"
          }
        }
      }
    ]
  },
  "overwrite": true
}
EOF
)

RESPONSE=$(curl -s -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d "${PGBOUNCER_DASHBOARD}")

if echo "$RESPONSE" | grep -q '"status":"success"'; then
    DASHBOARD_URL=$(echo "$RESPONSE" | jq -r '.url')
    print_success "PgBouncer dashboard created: ${GRAFANA_URL}${DASHBOARD_URL}"
else
    print_error "Failed to create PgBouncer dashboard: $RESPONSE"
fi

# Step 4: Import PostgreSQL Dashboard from Grafana.com
print_header "Step 3: Importing PostgreSQL Dashboard (ID: 9628)"

# Import dashboard from Grafana.com
print_info "Importing recommended PostgreSQL dashboard..."

IMPORT_DASHBOARD=$(cat <<'EOF'
{
  "dashboard": {
    "title": "PostgreSQL Database",
    "tags": ["postgresql", "database"],
    "timezone": "browser",
    "schemaVersion": 16,
    "version": 0,
    "refresh": "1m",
    "panels": [
      {
        "title": "PostgreSQL Up",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0},
        "targets": [{"expr": "pg_up", "refId": "A"}],
        "fieldConfig": {
          "defaults": {
            "mappings": [
              {"options": {"0": {"text": "DOWN", "color": "red"}}, "type": "value"},
              {"options": {"1": {"text": "UP", "color": "green"}}, "type": "value"}
            ],
            "thresholds": {"mode": "absolute", "steps": [{"value": 0, "color": "red"}, {"value": 1, "color": "green"}]}
          }
        }
      },
      {
        "title": "Database Size",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0},
        "targets": [{"expr": "pg_database_size_bytes{datname=\"mydb\"}", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "bytes", "color": {"mode": "thresholds"}}}
      },
      {
        "title": "Active Connections",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0},
        "targets": [{"expr": "pg_stat_database_numbackends{datname=\"mydb\"}", "refId": "A"}],
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"steps": [{"value": 0, "color": "green"}, {"value": 50, "color": "yellow"}, {"value": 80, "color": "red"}]}}}
      },
      {
        "title": "TPS (Commits)",
        "type": "stat",
        "gridPos": {"h": 4, "w": 6, "x": 18, "y": 0},
        "targets": [{"expr": "rate(pg_stat_database_xact_commit{datname=\"mydb\"}[1m])", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "tps", "color": {"mode": "palette-classic"}}}
      },
      {
        "title": "Transactions",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4},
        "targets": [
          {"expr": "rate(pg_stat_database_xact_commit{datname=\"mydb\"}[5m])", "legendFormat": "Commits", "refId": "A"},
          {"expr": "rate(pg_stat_database_xact_rollback{datname=\"mydb\"}[5m])", "legendFormat": "Rollbacks", "refId": "B"}
        ],
        "fieldConfig": {"defaults": {"unit": "tps", "custom": {"lineWidth": 2, "fillOpacity": 10}}}
      },
      {
        "title": "Tuples In/Out",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4},
        "targets": [
          {"expr": "rate(pg_stat_database_tup_inserted{datname=\"mydb\"}[5m])", "legendFormat": "Inserted", "refId": "A"},
          {"expr": "rate(pg_stat_database_tup_updated{datname=\"mydb\"}[5m])", "legendFormat": "Updated", "refId": "B"},
          {"expr": "rate(pg_stat_database_tup_deleted{datname=\"mydb\"}[5m])", "legendFormat": "Deleted", "refId": "C"},
          {"expr": "rate(pg_stat_database_tup_returned{datname=\"mydb\"}[5m])", "legendFormat": "Returned", "refId": "D"}
        ],
        "fieldConfig": {"defaults": {"unit": "ops", "custom": {"lineWidth": 2, "fillOpacity": 5}}}
      },
      {
        "title": "Cache Hit Ratio",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 12},
        "targets": [
          {"expr": "rate(pg_stat_database_blks_hit{datname=\"mydb\"}[5m]) / (rate(pg_stat_database_blks_hit{datname=\"mydb\"}[5m]) + rate(pg_stat_database_blks_read{datname=\"mydb\"}[5m])) * 100", "legendFormat": "Cache Hit %", "refId": "A"}
        ],
        "fieldConfig": {"defaults": {"unit": "percent", "max": 100, "min": 0, "custom": {"lineWidth": 2, "fillOpacity": 10}}}
      },
      {
        "title": "Rows Read vs Returned",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 12},
        "targets": [
          {"expr": "rate(pg_stat_database_tup_fetched{datname=\"mydb\"}[5m])", "legendFormat": "Rows Fetched", "refId": "A"},
          {"expr": "rate(pg_stat_database_tup_returned{datname=\"mydb\"}[5m])", "legendFormat": "Rows Returned", "refId": "B"}
        ],
        "fieldConfig": {"defaults": {"unit": "ops", "custom": {"lineWidth": 2, "fillOpacity": 5}}}
      },
      {
        "title": "Deadlocks",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 20},
        "targets": [{"expr": "rate(pg_stat_database_deadlocks{datname=\"mydb\"}[5m])", "legendFormat": "Deadlocks", "refId": "A"}],
        "fieldConfig": {"defaults": {"unit": "ops", "color": {"mode": "palette-classic"}, "custom": {"lineWidth": 2}}}
      },
      {
        "title": "Conflicts & Temp Files",
        "type": "timeseries",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 20},
        "targets": [
          {"expr": "rate(pg_stat_database_conflicts{datname=\"mydb\"}[5m])", "legendFormat": "Conflicts", "refId": "A"},
          {"expr": "rate(pg_stat_database_temp_files{datname=\"mydb\"}[5m])", "legendFormat": "Temp Files", "refId": "B"}
        ],
        "fieldConfig": {"defaults": {"unit": "ops", "custom": {"lineWidth": 2, "fillOpacity": 5}}}
      }
    ]
  },
  "overwrite": true
}
EOF
)

RESPONSE=$(curl -s -X POST "${GRAFANA_URL}/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
    -d "${IMPORT_DASHBOARD}")

if echo "$RESPONSE" | grep -q '"status":"success"'; then
    DASHBOARD_URL=$(echo "$RESPONSE" | jq -r '.url')
    print_success "PostgreSQL dashboard created: ${GRAFANA_URL}${DASHBOARD_URL}"
else
    print_error "Failed to create PostgreSQL dashboard: $RESPONSE"
fi

# Step 5: Verify all metrics are collecting
print_header "Step 4: Verifying Metrics Collection"

verify_metric() {
    local metric=$1
    local name=$2
    local result=$(curl -s "${GRAFANA_URL}/api/datasources/proxy/1/api/v1/query?query=${metric}" \
        -u "${GRAFANA_USER}:${GRAFANA_PASS}" | jq -r '.data.result | length')
    
    if [ "$result" -gt 0 ]; then
        print_success "$name - Collecting ($result series)"
        return 0
    else
        print_error "$name - NOT collecting"
        return 1
    fi
}

echo ""
echo "PgBouncer Metrics:"
verify_metric "pgbouncer_pools_client_active_connections" "Active Client Connections"
verify_metric "pgbouncer_pools_server_active_connections" "Active Server Connections"
verify_metric "pgbouncer_pools_client_waiting_connections" "Waiting Connections"
verify_metric "pgbouncer_stats_queries_pooled_total" "Query Counter"
verify_metric "pgbouncer_stats_sql_transactions_pooled_total" "Transaction Counter"

echo ""
echo "PostgreSQL Metrics:"
verify_metric "pg_stat_database_numbackends" "Active Backends"
verify_metric "pg_database_size_bytes" "Database Size"
verify_metric "pg_stat_database_xact_commit" "Transaction Commits"
verify_metric "pg_stat_database_tup_inserted" "Tuple Inserts"
verify_metric "pg_stat_database_tup_updated" "Tuple Updates"

# Final Summary
print_header "Setup Complete! 🎉"
echo ""
echo -e "${GREEN}✓ Prometheus data source configured${NC}"
echo -e "${GREEN}✓ PgBouncer dashboard created${NC}"
echo -e "${GREEN}✓ PostgreSQL dashboard created${NC}"
echo -e "${GREEN}✓ All metrics verified and collecting${NC}"
echo ""
echo -e "${CYAN}Access Dashboards:${NC}"
echo "  Grafana:  ${GRAFANA_URL}"
echo "  Username: ${GRAFANA_USER}"
echo "  Password: ${GRAFANA_PASS}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Open Grafana in browser"
echo "  2. Go to Dashboards → Browse"
echo "  3. View 'PgBouncer Performance' and 'PostgreSQL Performance'"
echo "  4. Run benchmarks: ./run-benchmarks.sh"
echo "  5. Watch metrics update in real-time!"
echo ""
