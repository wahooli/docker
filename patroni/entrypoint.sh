#!/bin/bash
set -euo pipefail

# Define the script name for the logger and source the library.
SCRIPT_NAME="entrypoint"
source /logging.sh

# ====================================================================================
# --- Main Script Logic ---
# ====================================================================================

# --- 1. Validate required environment variables ---
if [ -z "${PATRONI_NAME:-}" ]; then
  log_error "PATRONI_NAME environment variable is not set"
  exit 1
fi

# --- 2. Set core script variables ---
PGDATA="/home/postgres/data/${PATRONI_NAME}"
BACKUP_ROOT_DIR="${PG_BACKUP_PATH:-/dbdump}"
PHYSICAL_BACKUP_PATH="$BACKUP_ROOT_DIR/physical"
LOGICAL_BACKUP_PATH="$BACKUP_ROOT_DIR/logical"
BASEBACKUP_FORMAT="${PG_BASEBACKUP_FORMAT:-tar}" # or "plain"
SKIP_RESTORE_CLEANUP="${SKIP_RESTORE_CLEANUP:-false}"

# --- Get current system information for comparison ---
CURRENT_CPU_ARCH=$(uname -m)
CURRENT_PG_MAJOR_VERSION=$(postgres --version | awk '{print $3}' | cut -d. -f1)

# --- 3. Check for existing data and restore if necessary ---
log_msg "Checking for existing PostgreSQL data directory..."
mkdir -p "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  log_msg "No PGDATA found. Checking for backups to restore..."
  log_msg "Current System: Arch=$CURRENT_CPU_ARCH, PG Version=$CURRENT_PG_MAJOR_VERSION"

  # Only attempt a restore if the backup directory exists and is not empty.
  if [ -d "$PHYSICAL_BACKUP_PATH" ] && [ -n "$(ls -A "$PHYSICAL_BACKUP_PATH" 2>/dev/null)" ]; then
    log_msg "Physical backup files detected. Validating metadata..."

    backup_arch=""
    backup_pg_version=""
    backup_is_compatible=false
    
    # --- Find the latest backup and check its metadata ---
    if [ "$BASEBACKUP_FORMAT" = "tar" ]; then
      latest_backup_file=$(find "$PHYSICAL_BACKUP_PATH" -maxdepth 1 -name 'basebackup-*.tar*' | sort -r | head -n1)
      if [ -n "$latest_backup_file" ]; then
        filename=$(basename "$latest_backup_file")
        backup_arch=$(echo "$filename" | cut -d'-' -f2)
        backup_pg_version=$(echo "$filename" | cut -d'-' -f3)
      fi
    elif [ "$BASEBACKUP_FORMAT" = "plain" ]; then
      latest_backup_dir=$(find "$PHYSICAL_BACKUP_PATH" -maxdepth 1 -type d -name 'basebackup-*' | sort -r | head -n1)
      if [ -n "$latest_backup_dir" ] && [ -f "$latest_backup_dir/backup_metadata.txt" ]; then
        . "$latest_backup_dir/backup_metadata.txt"
        backup_arch="$CPU_ARCH"
        backup_pg_version="$PG_MAJOR_VERSION"
      fi
    fi

    # --- Compare metadata and decide whether to restore ---
    if [ -n "$backup_arch" ] && [ "$backup_arch" = "$CURRENT_CPU_ARCH" ] && [ "$backup_pg_version" = "$CURRENT_PG_MAJOR_VERSION" ]; then
      backup_is_compatible=true
    fi

    if [ "$backup_is_compatible" = "true" ]; then
      log_msg "Compatible physical backup found. Starting restore..."
      log_msg "Backup Arch: $backup_arch, PG Version: $backup_pg_version"
      
      if [ "$BASEBACKUP_FORMAT" = "tar" ]; then
        log_msg "Extracting from $(basename "$latest_backup_file")..."
        tar -xf "$latest_backup_file" -C "$PGDATA"
      elif [ "$BASEBACKUP_FORMAT" = "plain" ]; then
        log_msg "Copying from $(basename "$latest_backup_dir")..."
        cp -a "$latest_backup_dir"/. "$PGDATA/"
      fi

      if [ "$SKIP_RESTORE_CLEANUP" != "true" ]; then
        log_msg "Cleaning up all backup directories after successful physical restore..."
        if [ -n "$BACKUP_ROOT_DIR" ] && [ "$BACKUP_ROOT_DIR" != "/" ]; then
          rm -rf "${BACKUP_ROOT_DIR:?}"/*
        else
          log_msg "Cleanup skipped due to potentially unsafe backup path." "warning"
        fi
      else
        log_msg "SKIP_RESTORE_CLEANUP is true. Removing redundant logical backup path only..."
        if [ -d "$LOGICAL_BACKUP_PATH" ]; then
            rm -rf "$LOGICAL_BACKUP_PATH"
        fi
      fi
      log_msg "Physical restore complete."
    else
      log_msg "No compatible physical backup found. Skipping physical restore." "warning"
      log_msg "Found: Arch=$backup_arch, PG Version=$backup_pg_version" "warning"
      log_msg "Needed: Arch=$CURRENT_CPU_ARCH, PG Version=$CURRENT_PG_MAJOR_VERSION" "warning"
      
      log_msg "Cleaning up incompatible physical backup directory..."
      if [ -n "$PHYSICAL_BACKUP_PATH" ] && [ "$PHYSICAL_BACKUP_PATH" != "/" ]; then
        rm -rf "$PHYSICAL_BACKUP_PATH"
      else
        log_msg "Cleanup of incompatible backup skipped due to potentially unsafe path." "warning"
      fi

      log_msg "Patroni will initialize a new, empty cluster."
    fi
  else
    log_msg "No backups found. Patroni will initialize a new, empty cluster."
  fi
else
  log_msg "PGDATA already exists, skipping restore."
fi

# Set correct permissions for the data directory
chmod 0700 "$PGDATA"

# --- 4. Start the main application (Patroni) ---
log_msg "Starting Patroni..."
expanded_args=()
for arg in "$@"; do
  expanded_args+=("$(envsubst <<< "$arg")")
done
exec "${expanded_args[@]}"
