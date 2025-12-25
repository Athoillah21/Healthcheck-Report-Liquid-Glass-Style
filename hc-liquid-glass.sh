#!/bin/bash

# ==============================================================================
# CONFIGURATION VARIABLES
# ==============================================================================
LIST_DB_FILE="/home/postgres/script/test_email/replication_mail/list_db_handover" # DB List file: HOSTNAME,IP,PORT,DBNAME,DISPLAY_NAME,MP
DB_USER="******" # PostgreSQL user for target DBs
DB_PASSWORD="******"

# PEM Database Connection
PEM_HOST="localhost"
PEM_PORT="****"
PEM_USER="*****"
PEM_DB="*****"

# Thresholds (New Logic Implemented)
DEAD_TUPLES_WARN_THRESHOLD=200000     # Dead Tuples threshold for WARNING (200k)
DEAD_TUPLES_ALERT_THRESHOLD=1000000   # Dead Tuples threshold for ALERT (1M)

XID_AGE_WARN_THRESHOLD=250000000      # XID Age threshold for WARNING (250M)
XID_AGE_ALERT_THRESHOLD=1000000000    # XID Age threshold for ALERT (1B)

CONN_WARN_PERCENT=80                  # Connection usage percentage for WARNING (80%)
CONN_ALERT_PERCENT=90                 # Connection usage percentage for ALERT (90%)

MOUNTPOINT_ALERT_THRESHOLD=70         # Mountpoint usage percentage for ALERT (70%)

REPLICATION_LAG_DELAY_BYTES=10485760  # 10MB replication lag for DELAY status

# Email Subject Line (Used for HTML title/header and Email subject)
SUBJECT="[Daily Report] PostgreSQL Database Handover Report Liquid"

# Generate output file with date and time
DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%H:%M:%S")
DATETIME=$(date +"%Y-%m-%d %H:%M:%S")
OUTPUT_HTML="/home/postgres/script/test_email/replication_mail/report/daily_handover_report_liquid_${DATETIME}.html"

# ==============================================================================
# HELPER FUNCTIONS (Rewritten to use BASH and AWK instead of BC)
# ==============================================================================

# Function to convert bytes to human-readable format (Pure Bash Integer Math)
human_readable_bytes() {
    local bytes=$1
    if (( bytes < 1024 )); then
        echo "${bytes} B"
    elif (( bytes < 1048576 )); then
        # Calculate KB using integer math
        echo "$(( bytes / 1024 )) KB"
    elif (( bytes < 1073741824 )); then
        # Calculate MB using integer math
        echo "$(( bytes / 1048576 )) MB"
    else
        # Calculate GB using integer math
        echo "$(( bytes / 1073741824 )) GB"
    fi
}

# Function to format large numbers (e.g., 1234567890 -> 1.23B) (Uses AWK for floating point)
format_large_number() {
    local num=$1
    # Check if num is defined and greater than 0
    if [[ -z "$num" || "$num" -eq 0 ]]; then
        echo "0"
        return
    fi

    if (( num >= 1000000000 )); then
        # Use Awk for precise floating point division (Billion)
        awk -v n="$num" "BEGIN {printf \"%.2fB\", n / 1000000000}"
    elif (( num >= 1000000 )); then
        # Use Awk for precise floating point division (Million)
        awk -v n="$num" "BEGIN {printf \"%.1fM\", n / 1000000}"
    else
        echo "$num"
    fi
}

# Function to run psql command and handle connection failure
run_psql_query() {
    local host=$1
    local port=$2
    local dbname=$3
    local query=$4
    # Connect using the appropriate user for the target DB
    # Note: This assumes .pgpass is set up for $DB_USER (for targets)
    psql -h "$host" -p "$port" -U "$DB_USER" -d "$dbname" -t -A -F"," -c "$query" 2>/dev/null
    return $?
}

# Function to run psql query on the PEM database
run_psql_query_pem() {
    local query=$1
    # Connect using the specific PEM user and DB configuration
    # Note: This assumes .pgpass is set up for $PEM_USER
    # We leave 2>/dev/null OFF for debugging the "N/A" mountpoint issue
    psql -h "$PEM_HOST" -p "$PEM_PORT" -U "$PEM_USER" -d "$PEM_DB" -t -A -F"," -c "$query"
    return $?
}

# ==============================================================================
# INITIAL CHECKS AND HTML SETUP
# ==============================================================================

# Check if list_db file exists
if [[ ! -f "$LIST_DB_FILE" ]]; then
    echo "Error: File '$LIST_DB_FILE' not found!"
    exit 1
fi

# Start HTML report
cat <<EOF > "$OUTPUT_HTML"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$SUBJECT - $DATE</title>
    <!-- No external dependencies - works fully offline -->
    <style>
        :root {
            /* Elegant Liquid Glass */
            --glass-bg: rgba(255, 255, 255, 0.75);
            --glass-border: rgba(255, 255, 255, 0.5);
            --glass-shadow: 0 8px 40px rgba(0, 60, 120, 0.08);

            --accent: #1d4ed8;
            --accent-light: #3b82f6;
            --accent-soft: #dbeafe;

            --text-primary: #111827;
            --text-secondary: #374151;
            --text-muted: #6b7280;

            /* Status Colors */
            --ok: #059669;
            --ok-bg: rgba(5, 150, 105, 0.1);
            --warn: #d97706;
            --warn-bg: rgba(217, 119, 6, 0.1);
            --alert: #dc2626;
            --alert-bg: rgba(220, 38, 38, 0.1);
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            min-height: 100vh;
            padding: 48px 24px;
            color: var(--text-primary);
            font-size: 15px;
            line-height: 1.5;
            background:
                radial-gradient(ellipse at 0% 0%, rgba(219, 234, 254, 0.8) 0%, transparent 50%),
                radial-gradient(ellipse at 100% 100%, rgba(191, 219, 254, 0.6) 0%, transparent 50%),
                linear-gradient(180deg, #f0f9ff 0%, #e0f2fe 50%, #bae6fd 100%);
            background-attachment: fixed;
        }

        .container {
            max-width: 1500px;
            margin: 0 auto;
        }

        /* Glass Card */
        .glass-card {
            background: var(--glass-bg);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border: 1px solid var(--glass-border);
            border-radius: 16px;
            box-shadow: var(--glass-shadow);
        }

        /* Elegant Header */
        .header {
            text-align: center;
            padding: 56px 48px;
            margin-bottom: 32px;
            position: relative;
            overflow: hidden;
        }

        .header::before {
            content: "";
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 4px;
            background: linear-gradient(90deg, var(--accent) 0%, var(--accent-light) 50%, #60a5fa 100%);
        }

        .header-badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 16px;
            background: var(--accent-soft);
            border-radius: 100px;
            font-size: 0.75rem;
            font-weight: 600;
            color: var(--accent);
            text-transform: uppercase;
            letter-spacing: 0.1em;
            margin-bottom: 20px;
        }

        .header-badge::before {
            content: "";
            width: 8px;
            height: 8px;
            background: var(--accent);
            border-radius: 50%;
        }

        .header h1 {
            font-size: 2.25rem;
            font-weight: 700;
            background: linear-gradient(135deg, var(--accent) 0%, var(--accent-light) 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 12px;
            letter-spacing: -0.02em;
        }

        .header .subtitle {
            font-size: 1.1rem;
            color: var(--text-secondary);
            font-weight: 400;
            margin-bottom: 28px;
        }

        .header-meta {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 24px;
            flex-wrap: wrap;
        }

        .meta-item {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            font-size: 0.9rem;
            color: var(--text-muted);
        }

        .meta-item strong {
            color: var(--text-primary);
            font-weight: 600;
        }

        .meta-divider {
            width: 4px;
            height: 4px;
            background: var(--text-muted);
            border-radius: 50%;
            opacity: 0.5;
        }

        .status-live {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 6px 14px;
            background: var(--ok-bg);
            border-radius: 100px;
            font-size: 0.8rem;
            font-weight: 600;
            color: var(--ok);
        }

        .status-live::before {
            content: "";
            width: 8px;
            height: 8px;
            background: var(--ok);
            border-radius: 50%;
            animation: pulse-dot 2s ease-in-out infinite;
        }

        @keyframes pulse-dot {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.5; transform: scale(0.8); }
        }

        /* Section Title */
        .section-title {
            display: flex;
            align-items: center;
            gap: 14px;
            font-size: 1.25rem;
            font-weight: 600;
            color: var(--text-primary);
            margin-bottom: 20px;
            padding-left: 4px;
        }

        .section-title::before {
            content: "";
            width: 4px;
            height: 24px;
            background: linear-gradient(180deg, var(--accent) 0%, var(--accent-light) 100%);
            border-radius: 2px;
        }

        /* Table */
        .table-container {
            overflow: hidden;
        }

        table {
            width: 100%;
            border-collapse: collapse;
        }

        thead {
            background: linear-gradient(135deg, var(--accent) 0%, var(--accent-light) 100%);
        }

        th {
            padding: 18px 16px;
            text-align: center;
            font-weight: 600;
            color: #ffffff;
            font-size: 0.8rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }

        td {
            padding: 20px 16px;
            text-align: center;
            border-bottom: 1px solid rgba(0, 0, 0, 0.05);
            font-size: 0.95rem;
            vertical-align: middle;
        }

        tbody tr:last-child td {
            border-bottom: none;
        }

        tbody tr:hover {
            background: rgba(29, 78, 216, 0.03);
        }

        .instance-name {
            font-weight: 600;
            color: var(--text-primary);
        }

        .hostname {
            font-family: 'SF Mono', 'Consolas', monospace;
            font-size: 0.875rem;
            color: var(--text-secondary);
        }

        /* Status Pills */
        .status-ok {
            background: var(--ok-bg);
            color: var(--ok);
            padding: 6px 14px;
            border-radius: 8px;
            font-size: 0.85rem;
            font-weight: 600;
            display: inline-block;
        }

        .status-warn {
            background: var(--warn-bg);
            color: var(--warn);
            padding: 6px 14px;
            border-radius: 8px;
            font-size: 0.85rem;
            font-weight: 600;
            display: inline-block;
        }

        .status-alert {
            background: var(--alert-bg);
            color: var(--alert);
            padding: 6px 14px;
            border-radius: 8px;
            font-size: 0.85rem;
            font-weight: 600;
            display: inline-block;
        }

        .status-na {
            background: rgba(107, 114, 128, 0.1);
            color: var(--text-muted);
            padding: 6px 14px;
            border-radius: 8px;
            font-size: 0.85rem;
            font-weight: 500;
            display: inline-block;
        }

        .status-safe {
            background: var(--ok-bg);
            color: var(--ok);
            padding: 6px 14px;
            border-radius: 8px;
            font-size: 0.85rem;
            font-weight: 600;
            display: inline-block;
        }

        /* Replication Badges */
        .repl-primary {
            background: linear-gradient(135deg, var(--accent) 0%, var(--accent-light) 100%);
            color: #ffffff;
            padding: 7px 16px;
            border-radius: 100px;
            font-size: 0.8rem;
            font-weight: 600;
            display: inline-block;
            text-transform: uppercase;
            letter-spacing: 0.02em;
            box-shadow: 0 2px 8px rgba(29, 78, 216, 0.3);
        }

        .repl-replica {
            background: linear-gradient(135deg, #0d9488 0%, #14b8a6 100%);
            color: #ffffff;
            padding: 7px 16px;
            border-radius: 100px;
            font-size: 0.8rem;
            font-weight: 600;
            display: inline-block;
            text-transform: uppercase;
            letter-spacing: 0.02em;
            box-shadow: 0 2px 8px rgba(13, 148, 136, 0.3);
        }

        .repl-unsync {
            background: linear-gradient(135deg, #dc2626 0%, #ef4444 100%);
            color: #ffffff;
            padding: 7px 16px;
            border-radius: 100px;
            font-size: 0.8rem;
            font-weight: 600;
            display: inline-block;
            text-transform: uppercase;
            letter-spacing: 0.02em;
            box-shadow: 0 2px 8px rgba(220, 38, 38, 0.3);
        }

        /* Role Badge */
        .role-master {
            background: var(--accent-soft);
            color: var(--accent);
            padding: 5px 12px;
            border-radius: 6px;
            font-size: 0.85rem;
            font-weight: 600;
            display: inline-block;
        }

        .role-slave {
            background: rgba(13, 148, 136, 0.12);
            color: #0d9488;
            padding: 5px 12px;
            border-radius: 6px;
            font-size: 0.85rem;
            font-weight: 600;
            display: inline-block;
        }

        small {
            display: block;
            font-size: 0.8rem;
            color: var(--text-muted);
            margin-top: 6px;
        }

        footer {
            text-align: center;
            padding: 40px 24px;
            color: var(--text-muted);
        }

        footer p {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            padding: 14px 28px;
            font-size: 0.9rem;
            background: var(--glass-bg);
            border: 1px solid var(--glass-border);
            border-radius: 100px;
            backdrop-filter: blur(16px);
        }

        footer p::before {
            content: "⚡";
        }

        /* Responsive */
        @media (max-width: 1200px) {
            .table-container { overflow-x: auto; }
            table { min-width: 1000px; }
        }

        @media (max-width: 768px) {
            body { padding: 24px 16px; font-size: 14px; }
            .header { padding: 40px 24px; }
            .header h1 { font-size: 1.75rem; }
            .header-meta { gap: 16px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <header class="header glass-card">
            <div class="header-badge">Daily Report</div>
            <h1>PostgreSQL Database Handover Report</h1>
            <p class="subtitle">Comprehensive Fleet Health Monitoring Dashboard</p>
            <div class="header-meta">
                <span class="meta-item"><strong>Date:</strong> $DATE</span>
                <span class="meta-divider"></span>
                <span class="meta-item"><strong>Time:</strong> $TIME WIB</span>
                <span class="meta-divider"></span>
                <span class="status-live">System Active</span>
            </div>
        </header>

        <h2 class="section-title">Instance Health Summary</h2>
        <div class="table-container glass-card">
            <table>
                <thead>
                    <tr>
                        <th>Instance</th>
                        <th>Hostname</th>
                        <th>Port</th>
                        <th>Role</th>
                        <th>Replication</th>
                        <th>Connections</th>
                        <th>Dead Tuples</th>
                        <th>XID Age</th>
                        <th>Blocking</th>
                        <th>Disk</th>
                    </tr>
                </thead>
                <tbody>
EOF

# ==============================================================================
# MAIN PROCESSING LOOP
# ==============================================================================

# Process each database entry in the list
while IFS=',' read -r HOSTNAME IP PORT DBNAME DISPLAY_NAME MP; do
    # Skip empty lines or comments
    if [[ -z "$HOSTNAME" || "$HOSTNAME" == \#* ]]; then
        continue
    fi

    echo "Checking $DISPLAY_NAME ($DBNAME) at $IP:$PORT..."

    # Initialize variables for current instance
    ROLE_STATUS=""
    REPL_DETAIL=""
    MASTER_STATUS="N/A" # <-- INITIALIZE NEW VARIABLE
    CONN_PERCENT="N/A"
    DEAD_TUPLES="N/A"
    XID_AGE="N/A"
    BLOCKING_COUNT="N/A"
    MOUNTPOINT_USAGE="N/A"

    CONN_STATUS_CLASS="status-na"
    DEAD_TUPLES_CLASS="status-na"
    XID_AGE_CLASS="status-na"
    BLOCKING_CLASS="status-na"
    MOUNTPOINT_CLASS="status-na"

    # ----------------------------------------------------
    # 1. Connection Check & Max Connections
    # ----------------------------------------------------
    CONN_QUERY="
        SELECT setting::integer AS max_conn,
               (SELECT count(*)::float FROM pg_stat_activity) AS current_conn
        FROM pg_settings WHERE name = 'max_connections';
    "
    # Pass $DBNAME as the third argument (database name)
    export PGPASSWORD="${DB_PASSWORD}"
    CONN_RESULT=$(run_psql_query "$IP" "$PORT" "$DBNAME" "$CONN_QUERY")
    PSQL_EXIT_CODE=$?
    unset PGPASSWORD

    if [[ $PSQL_EXIT_CODE -ne 0 ]]; then
        # Handle connection failure
        echo "Error: Failed to connect to $DISPLAY_NAME (Code $PSQL_EXIT_CODE). Check DB name ($DBNAME) or connection settings."

        # Output row with all N/A and an Alert status
        echo "<tr>
            <td>$DISPLAY_NAME</td>
            <td>$HOSTNAME</td>
            <td>$PORT</td>
            <td class='status-alert'>CONNECTION FAILED</td> <td class='repl-unsync'>CONNECTION FAILED</td>
            <td class='status-alert'>N/A</td>
            <td class='status-alert'>N/A</td>
            <td class='status-alert'>N/A</td>
            <td class='status-alert'>N/A</td>
            <td class='status-alert'>N/A</td>
          </tr>" >> "$OUTPUT_HTML"
        continue
    fi

    # If connection is OK, parse Connection result
    IFS=',' read -r MAX_CONN CURRENT_CONN <<< "$CONN_RESULT"

    if [[ -n "$MAX_CONN" && "$MAX_CONN" -ne 0 ]]; then
        # Calculate usage percentage using AWK (allows floating point division)
        CONN_RAW_PERCENT=$(awk "BEGIN {printf \"%.0f\", ($CURRENT_CONN * 100) / $MAX_CONN}")

        # Bash integer comparison
        if (( CONN_RAW_PERCENT >= CONN_ALERT_PERCENT )); then
            CONN_STATUS_CLASS="status-alert"
        elif (( CONN_RAW_PERCENT >= CONN_WARN_PERCENT )); then
            CONN_STATUS_CLASS="status-warn"
        else
            CONN_STATUS_CLASS="status-ok"
        fi
        CONN_PERCENT="${CURRENT_CONN}/${MAX_CONN} (${CONN_RAW_PERCENT}%)"
    fi

    # ----------------------------------------------------
    # 2. Get Replication Role and Lag (Efficient)
    # ----------------------------------------------------

    # First, a single, fast query to determine the role
    ROLE_CHECK_QUERY="SELECT pg_is_in_recovery();"
    # Use 'xargs' to trim whitespace from the result
    export PGPASSWORD="${DB_PASSWORD}"
    IS_REPLICA=$(run_psql_query "$IP" "$PORT" "$DBNAME" "$ROLE_CHECK_QUERY" | xargs)
    unset PGPASSWORD

    if [[ "$IS_REPLICA" == "f" ]]; then
        # === PRIMARY (MASTER) ROLE LOGIC ===
        MASTER_STATUS="Master"

        # Master-side stats:
        # - Exclude pg_basebackup from replica/streaming counts and lag
        # - Count how many pg_basebackup clients are connected
        MASTER_STATS_QUERY="
            SELECT
                count(*) FILTER (WHERE application_name <> 'pg_basebackup') AS replica_count,
                count(*) FILTER (WHERE state = 'streaming' AND application_name <> 'pg_basebackup') AS streaming_count,
                count(*) FILTER (WHERE application_name = 'pg_basebackup') AS backup_count,
                COALESCE(
                    max(
                        COALESCE(pg_wal_lsn_diff(sent_lsn, replay_lsn), 0)
                    ) FILTER (WHERE application_name <> 'pg_basebackup'),
                    0
                ) AS max_lag_bytes
            FROM pg_stat_replication;
        "

        export PGPASSWORD="${DB_PASSWORD}"
        MASTER_RESULT=$(run_psql_query "$IP" "$PORT" "$DBNAME" "$MASTER_STATS_QUERY")
        IFS=',' read -r REPLICA_COUNT STREAMING_COUNT BACKUP_COUNT MAX_LAG_BYTES <<< "$MASTER_RESULT"
        unset PGPASSWORD

        # Now, all logic is in Bash
        if [[ "$REPLICA_COUNT" -eq 0 && "$BACKUP_COUNT" -eq 0 ]]; then
            # No replicas and no backup clients
            ROLE_STATUS="<div class='repl-unsync'>UNSYNC</div>"
            REPL_DETAIL="<br/>(No Replicas)"

        # Rule 1: No streaming replicas (excluding backup). Check if a backup is running.
        elif [[ "$STREAMING_COUNT" -eq 0 ]]; then
            ROLE_STATUS="<div class='repl-unsync'>UNSYNC</div>"

            if [[ "$BACKUP_COUNT" -gt 0 ]]; then
                # Only pg_basebackup is connected → it's a backup session, not a standby
                REPL_DETAIL="<br/>(Backup Running)"
            else
                # Find out the state of one of the non-streaming, non-backup replicas
                STATE_QUERY="
                    SELECT state
                    FROM pg_stat_replication
                    WHERE application_name <> 'pg_basebackup'
                    AND state <> 'streaming'
                    LIMIT 1;
                "
                export PGPASSWORD="${DB_PASSWORD}"
                OTHER_STATE_RAW=$(run_psql_query "$IP" "$PORT" "$DBNAME" "$STATE_QUERY")
                OTHER_STATE=$(echo "$OTHER_STATE_RAW" | xargs) # Clean whitespace
                unset PGPASSWORD

                if [[ -n "$OTHER_STATE" ]]; then
                    # Capitalize first letter: e.g., "backup" -> "Backup"
                    OTHER_STATE_CAPPED=$(echo "${OTHER_STATE^}")
                    REPL_DETAIL="<br/>($OTHER_STATE_CAPPED)"
                else
                    REPL_DETAIL="<br/>(Not Streaming)"
                fi
            fi

        # Rule 2: Streaming replicas exist, but check lag (on standbys only, excluding backup clients)
        elif [[ "$MAX_LAG_BYTES" -gt "$REPLICATION_LAG_DELAY_BYTES" ]]; then
            HUMAN_LAG=$(human_readable_bytes "$MAX_LAG_BYTES")
            REPL_DETAIL="<br/>(Lag: $HUMAN_LAG)"
            ROLE_STATUS="<div class='repl-unsync'>DELAY</div>"

            # If a backup is also running, append a note
            if [[ "$BACKUP_COUNT" -gt 0 ]]; then
                REPL_DETAIL="$REPL_DETAIL, Backup Running"
            fi

        # Rule 3: Streaming replicas and low lag
        else
            ROLE_STATUS="<div class='repl-primary'>SYNC</div>"

            # Optionally show backup note if present
            if [[ "$BACKUP_COUNT" -gt 0 ]]; then
                REPL_DETAIL="$REPL_DETAIL, Backup Running"
            fi
        fi

    elif [[ "$IS_REPLICA" == "t" ]]; then
        # === REPLICA (SLAVE) ROLE LOGIC ===
        MASTER_STATUS="Slave"

        # Run ONE query to check the WAL receiver
        WAL_RECEIVER_QUERY="SELECT count(*) FROM pg_stat_wal_receiver;"
        export PGPASSWORD="${DB_PASSWORD}"
        WAL_RECEIVER_COUNT=$(run_psql_query "$IP" "$PORT" "$DBNAME" "$WAL_RECEIVER_QUERY" | xargs)
        unset PGPASSWORD

        if [[ "$WAL_RECEIVER_COUNT" -gt 0 ]]; then
            # Connected and streaming (sync)
            ROLE_STATUS="<div class='repl-replica'>SYNC</div>"
            REPL_DETAIL="<br/>(Replica)"
        else
            # Not connected or not streaming (unsync)
            ROLE_STATUS="<div class='repl-unsync'>UNSYNC</div>"
            REPL_DETAIL="<br/>(Receiver Down)"
        fi

    else
        MASTER_STATUS="Unknown"
        ROLE_STATUS="<div class='repl-unsync'>UNKNOWN</div>"
        REPL_DETAIL="<br/>(Role Check Failed)"
    fi

    # ----------------------------------------------------
    # 3. Dead Tuples Check (Max across all tables)
    # ----------------------------------------------------
    # Query returns schema, table name, and count
    DEAD_TUPLES_QUERY="
        SELECT schemaname, relname, n_dead_tup
        FROM pg_stat_user_tables
        ORDER BY n_dead_tup DESC
        LIMIT 1;
    "

    # Pass $DBNAME as the third argument (database name)
    export PGPASSWORD="${DB_PASSWORD}"
    DEAD_TUPLES_RESULT=$(run_psql_query "$IP" "$PORT" "$DBNAME" "$DEAD_TUPLES_QUERY")

    # Parse schema, table, and dead tuple count (comma-separated result)
    IFS=',' read -r SCHEMANAME RELNAME DEAD_TUPLES_RAW <<< "$DEAD_TUPLES_RESULT"
    unset PGPASSWORD

    # Use the raw number for comparison, default to 0 if result is empty
    DEAD_TUPLES_COMPARE=${DEAD_TUPLES_RAW:-0}

    # Apply NEW logic: >=1M ALERT, 200k-999k WARN
    if (( DEAD_TUPLES_COMPARE >= DEAD_TUPLES_ALERT_THRESHOLD )); then
        DEAD_TUPLES_CLASS="status-alert"
    elif (( DEAD_TUPLES_COMPARE >= DEAD_TUPLES_WARN_THRESHOLD )); then
        DEAD_TUPLES_CLASS="status-warn"
    else
        DEAD_TUPLES_CLASS="status-ok"
    fi

    # Format the number and combine with table name for display
    if [[ -n "$DEAD_TUPLES_RAW" && "$DEAD_TUPLES_RAW" -gt 0 ]]; then
        FORMATTED_COUNT=$(format_large_number "$DEAD_TUPLES_RAW")
        DEAD_TUPLES="${FORMATTED_COUNT}<br/><small>(${SCHEMANAME}.${RELNAME})</small>"
    else
        DEAD_TUPLES="0"
    fi

    # ----------------------------------------------------
    # 4. XID Age Check
    # ----------------------------------------------------
    XID_QUERY="
        SELECT COALESCE(MAX(age(datfrozenxid)), 0) FROM pg_database;
    "
    # Pass $DBNAME as the third argument (database name)
    export PGPASSWORD="${DB_PASSWORD}"
    XID_RESULT=$(run_psql_query "$IP" "$PORT" "$DBNAME" "$XID_QUERY")
    XID_AGE=$(echo "$XID_RESULT" | xargs)
    unset PGPASSWORD
    # Apply NEW logic: >=1B ALERT, 250M-999M WARN
    if (( XID_AGE >= XID_AGE_ALERT_THRESHOLD )); then
        XID_AGE_CLASS="status-alert"
    elif (( XID_AGE >= XID_AGE_WARN_THRESHOLD )); then
        XID_AGE_CLASS="status-warn"
    else
        XID_AGE_CLASS="status-ok"
    fi

    XID_AGE=$(format_large_number "$XID_AGE")

    # ----------------------------------------------------
    # 5. Blocking Queries Count (MODIFIED)
    # ----------------------------------------------------
    BLOCKING_QUERY="
        SELECT COUNT(*) AS not_granted_lock_count
        FROM pg_locks
        WHERE NOT granted;
    "
    # Pass $DBNAME as the third argument (database name)
    export PGPASSWORD="${DB_PASSWORD}"
    BLOCKING_RESULT=$(run_psql_query "$IP" "$PORT" "$DBNAME" "$BLOCKING_QUERY")
    BLOCKING_COUNT=$(echo "$BLOCKING_RESULT" | xargs)
    unset PGPASSWORD
    # Apply NEW logic: 1-10 WARN, >=11 ALERT
    if (( BLOCKING_COUNT >= 11 )); then
        BLOCKING_CLASS="status-alert"
    elif (( BLOCKING_COUNT >= 1 )); then
        BLOCKING_CLASS="status-warn"
    else
        BLOCKING_CLASS="status-ok"
    fi

    # ----------------------------------------------------
    # 6. Mountpoint Usage Check (from PEM database)
    # ----------------------------------------------------
    # This query uses $HOSTNAME (field 1) and $DISPLAY_NAME (field 5) from the list_db file
    MOUNTPOINT_QUERY="
      SELECT ROUND((d.space_used_mb::numeric / d.size_mb) * 100, 2) AS usage_percent
      FROM pemdata.disk_space d
      JOIN pem.agent a ON d.agent_id = a.id
      WHERE d.mount_point LIKE '%${MP}'
        AND a.description LIKE '%${HOSTNAME}%'
        AND d.size_mb > 0 -- Avoid division by zero
      ORDER BY d.recorded_time DESC
      LIMIT 1;
    "

    # Run query against the PEM database
    export PGPASSWORD="${DB_PASSWORD}"
    MOUNTPOINT_RESULT=$(run_psql_query_pem "$MOUNTPOINT_QUERY")
    PEM_QUERY_EXIT_CODE=$?
    unset PGPASSWORD
    # Check if the query returned a result
    if [[ $PEM_QUERY_EXIT_CODE -eq 0 && -n "$MOUNTPOINT_RESULT" ]]; then
        # The $MOUNTPOINT_RESULT is the percentage string (e.g., "85.23")
        MOUNTPOINT_PERCENT_STRING=$(echo "$MOUNTPOINT_RESULT" | xargs) # Trim whitespace

        # Use AWK to convert the percentage string (e.g., "85.23") to an integer
        MOUNTPOINT_RAW_PERCENT=$(echo "$MOUNTPOINT_PERCENT_STRING" | awk '{printf "%.0f", $1}')

        # NEW 80% THRESHOLD LOGIC (SAFE/ALERT)
        if (( MOUNTPOINT_RAW_PERCENT >= MOUNTPOINT_ALERT_THRESHOLD )); then
            MOUNTPOINT_CLASS="status-alert"
            MOUNTPOINT_DISPLAY_TEXT="$MP"
        else
            MOUNTPOINT_CLASS="status-safe"
            MOUNTPOINT_DISPLAY_TEXT="$MP"
        fi

        # Format for display: e.g., "ALERT (85.23%)" or "SAFE (70.10%)"
        MOUNTPOINT_USAGE="${MOUNTPOINT_DISPLAY_TEXT}<br/><small>(${MOUNTPOINT_PERCENT_STRING}%)</small>"
    else
        # Query failed or returned no data
        MOUNTPOINT_CLASS="status-na"
        MOUNTPOINT_USAGE="N/A"
    fi

    # ----------------------------------------------------
    # FINAL HTML ROW OUTPUT
    # ----------------------------------------------------
    echo "<tr>
        <td>$DISPLAY_NAME</td>
        <td>$HOSTNAME</td>
        <td>$PORT</td>
        <td>$MASTER_STATUS</td> <td>$ROLE_STATUS $REPL_DETAIL</td>
        <td><div class='$CONN_STATUS_CLASS'>$CONN_PERCENT</div></td>
        <td><div class='$DEAD_TUPLES_CLASS'>$DEAD_TUPLES</div></td>
        <td><div class='$XID_AGE_CLASS'>$XID_AGE</div></td>
        <td><div class='$BLOCKING_CLASS'>$BLOCKING_COUNT</div></td>
        <td><div class='$MOUNTPOINT_CLASS'>$MOUNTPOINT_USAGE</div></td>
      </tr>" >> "$OUTPUT_HTML"

done < "$LIST_DB_FILE"

# ==============================================================================
# HTML FOOTER AND EMAIL SENDING
# ==============================================================================

# Finish HTML file
echo '            </tbody>
            </table>
        </div>
    </div>
    <footer>
        <p>Generated by PostgreSQL Healthcheck Report Script - Telkomsigma</p>
    </footer>
</body>
</html>' >> "$OUTPUT_HTML"


# --- Email Sending ---
# Define email recipients and sender.
TO_EMAIL="abasawatawallah@gmail.co.id"
FROM_EMAIL="lalalala@gmail.co.id"

(
echo "Dear Team,"
echo "" # Empty line for spacing
echo "Attached is the latest PostgreSQL Database Healthcheck Report for your review. Please examine the findings carefully. If any metrics or indicators fall outside the expected operational thresholds or best practices, kindly initiate the appropriate remediation procedures as soon as possible to ensure continued system stability and performance."
echo "" # Empty line for spacing
echo "Best regards,"
echo "MODB Team"
) | mailx -s "$SUBJECT" -a "$OUTPUT_HTML" -r "$FROM_EMAIL" "$TO_EMAIL"

echo "Health check report sent to $TO_EMAIL."