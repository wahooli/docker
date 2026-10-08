#!/bin/bash
set -euo pipefail

LOG_FORMAT="${BACKUP_LOG_FORMAT:-plain}"
# Define the script name for the logger and source the library.
SCRIPT_NAME="backup"
source /logging.sh

# ====================================================================================
# --- Configuration & Validation ---
# ====================================================================================

# --- General Settings ---
BACKUP_ROOT_DIR="${PG_BACKUP_PATH:-/dbdump}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# --- Get system information for filename ---
CPU_ARCH=$(uname -m)
PG_MAJOR_VERSION=$(postgres --version | awk '{print $3}' | cut -d. -f1)

# --- Physical Backup Settings ---
PHYSICAL_BACKUP_DIR="$BACKUP_ROOT_DIR/physical"
PG_BASEBACKUP_FORMAT="${PG_BASEBACKUP_FORMAT:-tar}" # 'tar' or 'plain'
PG_INCLUDE_WAL="${PG_INCLUDE_WAL:-fetch}"
PG_COMPRESS_BACKUP="${PG_COMPRESS_BACKUP:-true}"
PG_COMPRESS_LEVEL="${PG_COMPRESS_LEVEL:-6}"

# --- Logical Backup Settings ---
LOGICAL_BACKUP_DIR="$BACKUP_ROOT_DIR/logical"

# --- Connection Settings ---
export PGHOST="${PGHOST:-/var/run/postgresql}"
export PGPORT="${PGPORT:-5432}"

# --- Validate required environment variables ---
if [ -z "${PATRONI_SUPERUSER_USERNAME:-}" ]; then
  log_error "PATRONI_SUPERUSER_USERNAME must be set for logical backups."
  exit 1
fi
if [ -z "${PATRONI_SUPERUSER_PASSWORD:-}" ]; then
  log_error "PATRONI_SUPERUSER_PASSWORD must be set for logical backups."
  exit 1
fi
if [ -z "${PATRONI_REPLICATION_USERNAME:-}" ]; then
  log_error "PATRONI_REPLICATION_USERNAME must be set for physical backups."
  exit 1
fi
if [ -z "${PATRONI_REPLICATION_PASSWORD:-}" ]; then
  log_error "PATRONI_REPLICATION_PASSWORD must be set for physical backups."
  exit 1
fi

# ====================================================================================
# --- Main Backup Logic ---
# ====================================================================================

log_msg "Starting backup process..."
log_msg "Detected Architecture: $CPU_ARCH"
log_msg "Detected PostgreSQL Version: $PG_MAJOR_VERSION"

# --- 1. Physical Backup (pg_basebackup) ---
(
  [ "plain" = "$LOG_FORMAT" ] && log_msg "--------------------------------------------------"
  log_msg "Starting PHYSICAL backup (pg_basebackup)..."
  
  # Set credentials for the replication user
  export PGUSER="${PATRONI_REPLICATION_USERNAME}"
  export PGPASSWORD="${PATRONI_REPLICATION_PASSWORD}"
  
  mkdir -p "$PHYSICAL_BACKUP_DIR"
  log_msg "User: $PGUSER"
  log_msg "Format: $PG_BASEBACKUP_FORMAT"

  # Construct the base filename with metadata
  base_filename="basebackup-${CPU_ARCH}-${PG_MAJOR_VERSION}-${TIMESTAMP}"

  if [ "$PG_BASEBACKUP_FORMAT" = "tar" ]; then
    backup_cmd=(pg_basebackup -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w -F tar -X "$PG_INCLUDE_WAL" -P)
    if [ "$PG_COMPRESS_BACKUP" = "true" ]; then
      TARGET_FILE="$PHYSICAL_BACKUP_DIR/${base_filename}.tar.gz"
      log_msg "Target file: $TARGET_FILE"
      backup_cmd+=("-D" "-")
      "${backup_cmd[@]}" | gzip -"$PG_COMPRESS_LEVEL" > "$TARGET_FILE"
    else
      TARGET_FILE="$PHYSICAL_BACKUP_DIR/${base_filename}.tar"
      log_msg "Target file: $TARGET_FILE"
      backup_cmd+=("-D" "$TARGET_FILE")
      "${backup_cmd[@]}"
    fi
  elif [ "$PG_BASEBACKUP_FORMAT" = "plain" ]; then
    TARGET_DIR="$PHYSICAL_BACKUP_DIR/${base_filename}"
    log_msg "Target directory: $TARGET_DIR"
    backup_cmd=(pg_basebackup -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -w -F plain -X "$PG_INCLUDE_WAL" -P -D "$TARGET_DIR")
    if [ "$PG_COMPRESS_BACKUP" = "true" ]; then
      backup_cmd+=("--compress=gzip:level=$PG_COMPRESS_LEVEL")
    fi
    "${backup_cmd[@]}"
    
    # Create a metadata file inside the plain backup directory
    log_msg "Creating metadata file..."
    metadata_file="$TARGET_DIR/backup_metadata.txt"
    {
      echo "CPU_ARCH=$CPU_ARCH"
      echo "PG_MAJOR_VERSION=$PG_MAJOR_VERSION"
      echo "BACKUP_TIMESTAMP=$TIMESTAMP"
    } > "$metadata_file"

  else
    log_error "Unsupported physical backup format: $PG_BASEBACKUP_FORMAT"
    exit 1
  fi
  
  log_msg "Physical backup complete."
) || { log_error "FATAL: Physical backup failed."; exit 1; }


# --- 2. Logical Backup (pg_dump) ---
(
  [ "plain" = "$LOG_FORMAT" ] && log_msg "--------------------------------------------------"
  log_msg "Starting LOGICAL backup (pg_dump)..."

  # Set credentials for the superuser
  export PGUSER="${PATRONI_SUPERUSER_USERNAME}"
  export PGPASSWORD="${PATRONI_SUPERUSER_PASSWORD}"

  mkdir -p "$LOGICAL_BACKUP_DIR"
  log_msg "User: $PGUSER"

  # Dump global objects (roles, tablespaces)
  log_msg "Dumping global objects..."
  pg_dumpall --globals-only --file="$LOGICAL_BACKUP_DIR/globals.sql"
  
  # Dump each database individually, excluding the 'postgres' database.
  log_msg "Finding all non-template databases to dump (excluding 'postgres')..."
  psql -w -At -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';" | while IFS= read -r db_name; do
    if [ -n "$db_name" ]; then
      log_msg "Dumping database: '$db_name'"
      pg_dump -w -Fc --clean --if-exists --create "$db_name" --file="$LOGICAL_BACKUP_DIR/${db_name}.dump"
    fi
  done

  log_msg "Logical backup complete."
) || { log_error "FATAL: Logical backup failed."; exit 1; }


[ "plain" = "$LOG_FORMAT" ] && log_msg "--------------------------------------------------"
log_msg "Backup process finished successfully."
