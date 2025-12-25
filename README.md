# PostgreSQL Database Healthcheck Report Script

A comprehensive Bash script that generates elegant, **Liquid Glass-styled** HTML health reports for PostgreSQL database fleets. The script monitors multiple database instances and sends automated email reports.

---

## ✨ Features

- **Multi-Instance Monitoring** — Monitors multiple PostgreSQL databases from a single configuration file
- **Beautiful HTML Reports** — Generates responsive, liquid glass-styled reports that work offline
- **Replication Monitoring** — Detects Primary/Replica roles and sync status
- **Automated Email Delivery** — Sends reports via `mailx` with HTML attachment
- **Customizable Thresholds** — Configurable warning and alert thresholds

---

## 📊 Health Metrics Monitored

| Metric | Description | Warning Threshold | Alert Threshold |
|--------|-------------|-------------------|-----------------|
| **Connections** | Current vs max connection usage | ≥80% | ≥90% |
| **Dead Tuples** | Largest dead tuple count per table | ≥200K | ≥1M |
| **XID Age** | Transaction ID age for wraparound prevention | ≥250M | ≥1B |
| **Blocking Queries** | Count of locks not granted | ≥1 | ≥11 |
| **Disk Usage** | Mountpoint usage from PEM database | - | ≥70% |
| **Replication Lag** | Byte lag between primary and replica | - | ≥10MB |

---

## 🔧 Configuration

### Main Variables (Lines 6-37)

```bash
# Database list file (CSV format)
LIST_DB_FILE="/home/postgres/script/test_email/replication_mail/list_db_handover"

# Target DB credentials
DB_USER="your_user"
DB_PASSWORD="your_password"

# PEM Database connection (for disk usage monitoring)
PEM_HOST="localhost"
PEM_PORT="5432"
PEM_USER="pem_user"
PEM_DB="pem"

# Output location
OUTPUT_HTML="/path/to/report/daily_handover_report_liquid_${DATETIME}.html"
```

### Database List File Format

The `list_db_handover` file uses CSV format with 6 fields:

```
HOSTNAME,IP,PORT,DBNAME,DISPLAY_NAME,MOUNTPOINT
```

**Example:**
```
server1,10.0.0.1,5432,production_db,Production Server,/data
server2,10.0.0.2,5432,staging_db,Staging Server,/data
```

| Field | Description |
|-------|-------------|
| `HOSTNAME` | Server hostname (used for PEM queries) |
| `IP` | IP address of the PostgreSQL server |
| `PORT` | PostgreSQL port number |
| `DBNAME` | Database name to connect to |
| `DISPLAY_NAME` | Human-readable name for reports |
| `MOUNTPOINT` | Disk mount point to monitor |

---

## 🔄 How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SCRIPT WORKFLOW                                │
└─────────────────────────────────────────────────────────────────────────────┘

   ┌──────────────────┐
   │  Read list_db    │
   │  configuration   │
   └────────┬─────────┘
            │
            ▼
   ┌──────────────────┐
   │  Generate HTML   │
   │  header + CSS    │
   └────────┬─────────┘
            │
            ▼
┌───────────────────────────────────────┐
│   FOR EACH DATABASE ENTRY:            │
│   ┌─────────────────────────────────┐ │
│   │ 1. Connection Check             │ │
│   │    └── Query pg_stat_activity   │ │
│   ├─────────────────────────────────┤ │
│   │ 2. Replication Status           │ │
│   │    ├── Check pg_is_in_recovery()│ │
│   │    ├── Query pg_stat_replication│ │
│   │    └── Query pg_stat_wal_receiver│ │
│   ├─────────────────────────────────┤ │
│   │ 3. Dead Tuples Check            │ │
│   │    └── Query pg_stat_user_tables│ │
│   ├─────────────────────────────────┤ │
│   │ 4. XID Age Check                │ │
│   │    └── Query pg_database        │ │
│   ├─────────────────────────────────┤ │
│   │ 5. Blocking Queries             │ │
│   │    └── Query pg_locks           │ │
│   ├─────────────────────────────────┤ │
│   │ 6. Disk Usage (from PEM)        │ │
│   │    └── Query pemdata.disk_space │ │
│   ├─────────────────────────────────┤ │
│   │ 7. Generate HTML table row      │ │
│   └─────────────────────────────────┘ │
└───────────────────────────────────────┘
            │
            ▼
   ┌──────────────────┐
   │  Close HTML file │
   └────────┬─────────┘
            │
            ▼
   ┌──────────────────┐
   │  Send Email via  │
   │     mailx        │
   └──────────────────┘
```

---

## 🎨 Report Status Indicators

### Replication Status

| Badge | Meaning |
|-------|---------|
| **SYNC** (blue) | Primary with healthy streaming replicas |
| **SYNC** (teal) | Replica actively streaming from primary |
| **DELAY** (red) | Replication lag exceeds 10MB |
| **UNSYNC** (red) | No replicas, receiver down, or not streaming |

### Metric Status Colors

| Class | Color | Meaning |
|-------|-------|---------|
| `status-ok` | 🟢 Green | Within normal parameters |
| `status-warn` | 🟡 Orange | Approaching threshold |
| `status-alert` | 🔴 Red | Exceeded critical threshold |
| `status-safe` | 🟢 Green | Disk usage safe |
| `status-na` | ⚪ Gray | Data not available |

---

## 📁 File Structure

```
📂 Healthcheck-Report-Consolidation-Server-Liquid-Glass-Style/
├── 📄 hc-liquid-glass.sh      # Main healthcheck script
├── 📄 list_db_handover        # Database configuration file
└── 📄 README.md               # This documentation
```

---

## ⚙️ Prerequisites

1. **PostgreSQL Client** — `psql` command must be available
2. **Mail Utility** — `mailx` for sending email reports
3. **Bash Shell** — Script uses Bash-specific features
4. **Network Access** — Script must reach all target databases
5. **PEM Database** — For disk usage monitoring (optional)

### Authentication Setup

Configure `.pgpass` file for passwordless authentication:

```
# ~/.pgpass format: hostname:port:database:username:password
10.0.0.1:5432:*:db_user:password
localhost:5432:pem:pem_user:password
```

---

## 🚀 Usage

### Make the script executable:

```bash
chmod +x hc-liquid-glass.sh
```

### Run the script:

```bash
./hc-liquid-glass.sh
```

### Schedule with Cron (Daily at 8 AM):

```bash
0 8 * * * /path/to/hc-liquid-glass.sh >> /var/log/healthcheck.log 2>&1
```

---

## 📧 Email Configuration

Modify the email settings at the bottom of the script (lines 919-920):

```bash
TO_EMAIL="recipient@example.com"
FROM_EMAIL="sender@example.com"
```

---

## 📝 Output Example

The script generates a beautiful HTML report featuring:

- **Glassmorphism Design** — Frosted glass effect with blur backdrop
- **Responsive Layout** — Works on desktop and mobile
- **Color-Coded Status** — Quick visual identification of issues
- **Offline Compatible** — No external dependencies (CSS embedded)
- **Animated Elements** — Subtle pulse animation on system status

---

## 🔧 Customizing Thresholds

Edit lines 17-28 to adjust thresholds:

```bash
DEAD_TUPLES_WARN_THRESHOLD=200000     # Warning at 200K
DEAD_TUPLES_ALERT_THRESHOLD=1000000   # Alert at 1M

XID_AGE_WARN_THRESHOLD=250000000      # Warning at 250M
XID_AGE_ALERT_THRESHOLD=1000000000    # Alert at 1B

CONN_WARN_PERCENT=80                  # Warning at 80%
CONN_ALERT_PERCENT=90                 # Alert at 90%

MOUNTPOINT_ALERT_THRESHOLD=70         # Alert at 70%

REPLICATION_LAG_DELAY_BYTES=10485760  # 10MB lag threshold
```

---

## 📜 License

This script was generated for PostgreSQL database fleet monitoring purposes.

---

**Generated by PostgreSQL Healthcheck Report Script - Telkomsigma**
