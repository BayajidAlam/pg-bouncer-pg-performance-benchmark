# PgBouncer Database Setup Automation

This repository contains Ansible automation for setting up a complete PostgreSQL database infrastructure with PgBouncer connection pooling, Prometheus monitoring, and Grafana visualization.

## Overview

The automation sets up:

1. **Database Server** (Private Subnet):

   - PostgreSQL 14+ database
   - PgBouncer connection pooler
   - PostgreSQL Exporter (metrics on port 9187)
   - PgBouncer Exporter (metrics on port 9127)

2. **Monitoring Server** (Public Subnet):
   - Prometheus (metrics collection on port 9090)
   - Grafana (visualization on port 3000)

## Architecture

```
┌─────────────────────────────────────────┐
│         Monitoring Server               │
│         (Public Subnet)                 │
│                                         │
│  ┌──────────────┐  ┌──────────────┐   │
│  │  Prometheus  │  │   Grafana    │   │
│  │   :9090      │  │    :3000     │   │
│  └──────────────┘  └──────────────┘   │
└─────────────┬───────────────────────────┘
              │ Scrapes Metrics
              │
┌─────────────▼───────────────────────────┐
│         Database Server                 │
│         (Private Subnet)                │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │       PostgreSQL (:5432)         │  │
│  └──────────────┬───────────────────┘  │
│                 │                       │
│  ┌──────────────▼───────────────────┐  │
│  │       PgBouncer (:6432)          │  │
│  └──────────────────────────────────┘  │
│                                         │
│  ┌──────────────┐  ┌──────────────┐   │
│  │ PostgreSQL   │  │  PgBouncer   │   │
│  │ Exporter     │  │  Exporter    │   │
│  │  :9187       │  │   :9127      │   │
│  └──────────────┘  └──────────────┘   │
└─────────────────────────────────────────┘
```

## Prerequisites

### Infrastructure Setup

Before running Ansible automation, ensure your infrastructure is provisioned:

1. **Pulumi Infrastructure** (in `infra/` directory):

   ```bash
   cd infra
   pulumi up
   ```

2. **AWS Resources Created**:

   - VPC with public and private subnets
   - EC2 instances (db-server and monitoring-server)
   - Security groups with proper port configurations
   - NAT Gateway for private subnet internet access

3. **SSH Configuration**:
   - Key pair created: `~/.ssh/db-cluster.id_rsa`
   - SSH config file updated with bastion jump configuration

### Local Requirements

- Ansible 2.9+
- Python 3.8+
- SSH access to servers

## Configuration

### 1. Update Inventory File

Edit `ansible/inventory.ini` with your server IPs:

```ini
[db]
db-server ansible_host=<DB_PRIVATE_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/db-cluster.id_rsa ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyJump=ubuntu@<MONITORING_PUBLIC_IP>'

[monitoring]
monitoring-server ansible_host=<MONITORING_PUBLIC_IP> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/db-cluster.id_rsa
```

Replace:

- `<DB_PRIVATE_IP>`: Private IP of database server
- `<MONITORING_PUBLIC_IP>`: Public IP of monitoring server

### 2. Customize Variables

Edit variables in `ansible/playbooks/setup-db-server.yml`:

```yaml
vars:
  db_name: "mydb" # Database name
  db_user: "myuser" # Database user
  db_password: "mypassword" # Database password
  postgresql_max_connections: 100 # PostgreSQL max connections
  pgbouncer_max_client_conn: 100 # PgBouncer max client connections
  pgbouncer_default_pool_size: 20 # Default pool size
```

## Usage

### Quick Start

Run the complete setup with one command:

```bash
./QUICKSTART.sh
```

This script will:

1. Verify Ansible installation
2. Check inventory configuration
3. Run the full setup playbook
4. Display access information

### Manual Setup

#### 1. Test Connectivity

```bash
ansible all -i ansible/inventory.ini -m ping
```

#### 2. Setup Database Server Only

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/setup-db-server.yml
```

This sets up:

- PostgreSQL database
- PgBouncer connection pooler
- Prometheus exporters

#### 3. Setup Monitoring Server Only

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/setup-monitoring.yml
```

This sets up:

- Prometheus
- Grafana

#### 4. Complete Setup

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/full-setup.yml
```

Runs both database and monitoring setup.

### Individual Components

Setup specific components:

```bash
# PostgreSQL only
ansible-playbook -i ansible/inventory.ini ansible/playbooks/setup-db-server.yml --tags postgres

# PgBouncer only
ansible-playbook -i ansible/inventory.ini ansible/playbooks/setup-db-server.yml --tags pgbouncer

# Exporters only
ansible-playbook -i ansible/inventory.ini ansible/playbooks/setup-db-server.yml --tags exporters
```

## Verification

### 1. Check Services

On database server:

```bash
ssh db-server
sudo systemctl status postgresql
sudo systemctl status pgbouncer
sudo systemctl status postgres-exporter
sudo systemctl status pgbouncer-exporter
```

### 2. Test Database Connection

Via PostgreSQL directly:

```bash
psql -h <DB_SERVER_IP> -p 5432 -U myuser -d mydb
```

Via PgBouncer:

```bash
psql -h <DB_SERVER_IP> -p 6432 -U myuser -d mydb
```

### 3. Check Metrics

PostgreSQL Exporter:

```bash
curl http://<DB_SERVER_IP>:9187/metrics
```

PgBouncer Exporter:

```bash
curl http://<DB_SERVER_IP>:9127/metrics
```

### 4. Access Monitoring

Prometheus:

- URL: `http://<MONITORING_IP>:9090`
- Check targets: Status → Targets

Grafana:

- URL: `http://<MONITORING_IP>:3000`
- Username: `admin`
- Password: `admin`

## Grafana Dashboard Setup

### 1. Add Prometheus Data Source

1. Login to Grafana
2. Go to Configuration → Data Sources
3. Click "Add data source"
4. Select "Prometheus"
5. Set URL: `http://prometheus:9090` (using Docker network)
6. Click "Save & Test"

### 2. Import Dashboards

Import pre-built dashboards:

**PostgreSQL Dashboard**:

- Dashboard ID: `9628`
- Name: PostgreSQL Database

**PgBouncer Dashboard**:

- Dashboard ID: `13125`
- Name: PgBouncer

Steps to import:

1. Click "+" → Import
2. Enter dashboard ID
3. Select Prometheus data source
4. Click "Import"

## Benchmark Testing

### Initialize pgbench

```bash
ssh db-server
pgbench -h localhost -p 6432 -U myuser -i mydb
```

### Run Benchmark

Simple test (10 clients, 100 transactions):

```bash
pgbench -h localhost -p 6432 -U myuser -c 10 -j 2 -t 100 mydb
```

Load test (50 clients, 1000 transactions):

```bash
pgbench -h localhost -p 6432 -U myuser -c 50 -j 4 -t 1000 mydb
```

### Monitor Performance

While running benchmark, monitor in Grafana:

- Active connections
- Query throughput
- Transaction rate
- Connection pool utilization

## Troubleshooting

### Connection Issues

1. **Can't connect to database**:

   ```bash
   # Check PostgreSQL is running
   sudo systemctl status postgresql

   # Check pg_hba.conf
   sudo cat /etc/postgresql/*/main/pg_hba.conf

   # Check PostgreSQL logs
   sudo tail -f /var/log/postgresql/postgresql-*.log
   ```

2. **Can't connect to PgBouncer**:

   ```bash
   # Check PgBouncer status
   sudo systemctl status pgbouncer

   # Check PgBouncer logs
   sudo tail -f /var/log/postgresql/pgbouncer.log

   # Test connection
   psql -h localhost -p 6432 -U myuser pgbouncer
   ```

### Exporter Issues

1. **Exporters not running**:

   ```bash
   # Check service status
   sudo systemctl status postgres-exporter
   sudo systemctl status pgbouncer-exporter

   # Check logs
   sudo journalctl -u postgres-exporter -f
   sudo journalctl -u pgbouncer-exporter -f
   ```

2. **Prometheus can't scrape metrics**:
   - Verify security group allows traffic on ports 9187 and 9127
   - Check exporters are listening: `netstat -tlnp | grep -E '9187|9127'`
   - Verify Prometheus configuration has correct DB server IP

### Monitoring Issues

1. **Prometheus not starting**:

   ```bash
   ssh monitoring-server
   cd ~/monitoring
   sudo docker-compose logs prometheus
   ```

2. **Grafana not accessible**:
   ```bash
   sudo docker-compose logs grafana
   # Check if port 3000 is open in security group
   ```

## Project Structure

```
pg-bouncer/
├── ansible.cfg                    # Ansible configuration
├── AUTOMATION_README.md           # This file
├── QUICKSTART.sh                  # Quick start script
├── setup.sh                       # Setup helper script
├── TEST_AND_RUN.sh               # Test and run script
│
├── ansible/
│   ├── inventory.ini             # Server inventory
│   │
│   ├── playbooks/
│   │   ├── full-setup.yml        # Complete setup playbook
│   │   ├── setup-db-server.yml   # Database server setup
│   │   ├── setup-monitoring.yml  # Monitoring server setup
│   │   └── benchmark.yml         # Benchmark testing
│   │
│   └── roles/
│       ├── postgres/             # PostgreSQL role
│       │   ├── tasks/
│       │   ├── templates/
│       │   └── handlers/
│       │
│       ├── pgbouncer/            # PgBouncer role
│       │   ├── tasks/
│       │   ├── templates/
│       │   └── handlers/
│       │
│       ├── exporters/            # Prometheus exporters role
│       │   ├── tasks/
│       │   ├── templates/
│       │   └── handlers/
│       │
│       └── prometheus/           # Prometheus + Grafana role
│           ├── tasks/
│           └── templates/
│
└── infra/                        # Pulumi infrastructure code
    ├── __main__.py
    ├── Pulumi.yaml
    └── requirements.txt
```

## Configuration Files

### PostgreSQL Configuration

- Location: `/etc/postgresql/*/main/postgresql.conf`
- Key settings:
  - `listen_addresses = '*'`
  - `max_connections = 100`
  - `password_encryption = md5`

### PgBouncer Configuration

- Location: `/etc/pgbouncer/pgbouncer.ini`
- Key settings:
  - `pool_mode = transaction`
  - `max_client_conn = 100`
  - `default_pool_size = 20`

### Prometheus Configuration

- Location: `~/monitoring/prometheus.yml`
- Scrape targets: PostgreSQL and PgBouncer exporters

## Best Practices

1. **Security**:

   - Change default passwords in production
   - Use strong passwords for database users
   - Restrict security group rules to specific IPs
   - Use SSL/TLS for database connections in production

2. **Performance**:

   - Tune `max_connections` based on your workload
   - Adjust PgBouncer pool sizes according to application needs
   - Monitor connection pool utilization
   - Use `transaction` pool mode for most applications

3. **Monitoring**:

   - Set up alerts in Prometheus for critical metrics
   - Monitor connection pool exhaustion
   - Track query performance
   - Watch for connection leaks

4. **Maintenance**:
   - Regular PostgreSQL backups
   - Keep exporters updated
   - Monitor disk space
   - Review and rotate logs

## Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [PgBouncer Documentation](https://www.pgbouncer.org/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## Support

For issues or questions:

1. Check the troubleshooting section
2. Review logs on respective servers
3. Verify security group configurations
4. Check Ansible playbook execution output

## License

This project is for educational purposes as part of the PgBouncer lab.
