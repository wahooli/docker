#!/bin/bash
set -euo pipefail
shopt -s nullglob

# Define the script name for the logger and source the library.
# The name is dynamically set based on how the script was called (e.g., post-bootstrap).
SCRIPT_NAME="post-hook"
source /logging.sh

# ====================================================================================
# --- Configuration & Validation ---
# ====================================================================================

# --- General Settings ---
CONNSTR="$1" # Patroni provides the connection string as the first argument.
BACKUP_ROOT_DIR="${PG_BACKUP_PATH:-/dbdump}"

# --- Logical Restore Settings ---
LOGICAL_BACKUP_PATH="$BACKUP_ROOT_DIR/logical"
PG_RESTORE_JOBS="${PG_RESTORE_JOBS:-1}"

# --- Standard Bootstrap Settings ---
# Parse the script name (e.g., post-bootstrap.sh) to determine the target directory.
script_basename=$(basename "$0")
PARSED_PART=${script_basename#post-}
PARSED_PART=${PARSED_PART%.sh}
TARGET_DIR="/docker-entrypoint-${PARSED_PART}.d"
# Update the script name for more specific logging
SCRIPT_NAME="post-${PARSED_PART}"

# --- Validate that this is a hook we should be handling ---
if [ "$PARSED_PART" != "bootstrap" ] && [ "$PARSED_PART" != "init" ]; then
    log_msg "Ignoring unrecognized hook '$script_basename'. Exiting."
    exit 0
fi

# ====================================================================================
# --- Main Logic ---
# ====================================================================================

# --- Path 1: Perform a Logical Restore ONLY for the 'bootstrap' hook AND if backups exist ---
if [ "$PARSED_PART" = "bootstrap" ] && [ -d "$LOGICAL_BACKUP_PATH" ] && [ -n "$(ls -A "$LOGICAL_BACKUP_PATH" 2>/dev/null)" ]; then
  log_msg "Logical backup directory found at '$LOGICAL_BACKUP_PATH'. Starting logical restore..."

  # Restore global objects first, connecting directly to the default database.
  if [ -f "$LOGICAL_BACKUP_PATH/globals.sql" ]; then
    log_msg "Restoring global objects..."
    psql -w "$CONNSTR" -f "$LOGICAL_BACKUP_PATH/globals.sql"
  fi

  # Restore individual database dumps.
  # pg_restore will connect using CONNSTR and create the new databases as specified in the dump files.
  for dump_file in "$LOGICAL_BACKUP_PATH"/*.dump; do
    log_msg "Restoring from: $(basename "$dump_file")"
    pg_restore -w -d "$CONNSTR" --clean --if-exists --create --jobs="$PG_RESTORE_JOBS" "$dump_file"
  done

  log_msg "Logical restore complete."
  
  # Clean up the entire backup directory contents after a successful restore.
  log_msg "Cleaning up root backup directory..."
  if [ -n "$BACKUP_ROOT_DIR" ] && [ "$BACKUP_ROOT_DIR" != "/" ]; then
    rm -rf "${BACKUP_ROOT_DIR:?}"/*
    log_msg "Backup directory cleaned."
  else
    log_msg "Cleanup skipped due to potentially unsafe backup path." "warning"
  fi

  # Exit successfully.
  exit 0

# --- Path 2: Perform Standard File-Based Bootstrap/Init ---
else
  # If this was the bootstrap hook but no logical backups were found, log it.
  if [ "$PARSED_PART" = "bootstrap" ]; then
      log_msg "No logical backups found to restore. Proceeding with standard file-based bootstrap..."
  fi

  if [ ! -d "${TARGET_DIR}" ]; then
    log_msg "Directory ${TARGET_DIR} does not exist, nothing to do." "warning"
    exit 0
  fi

  log_msg "Running initialization scripts from ${TARGET_DIR}..."

  find -L "$TARGET_DIR" -maxdepth 1 -type f | sort | while IFS= read -r f; do
    case "$f" in
      *.sql|*.psql)
        log_msg "Executing SQL script: $f"
        psql -w "$CONNSTR" -v ON_ERROR_STOP=1 -f "$f"
        ;;
      *.sql.gz|*.psql.gz)
        log_msg "Executing gzipped SQL script: $f"
        gunzip -c "$f" | psql -w "$CONNSTR" -v ON_ERROR_STOP=1
        ;;
      *.sh)
        log_msg "Running shell script: $f"
        # Pass the connection string to the shell script in case it needs it.
        bash "$f" "$CONNSTR"
        ;;
      *)
        log_msg "Ignoring unsupported file: $f"
        ;;
    esac
  done

  log_msg "All ${TARGET_DIR} scripts executed."
fi
