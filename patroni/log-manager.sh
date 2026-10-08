#!/bin/bash
set -euo pipefail

# Define the script name for the logger and source the library.
SCRIPT_NAME="log-manager"
source /logging.sh

# ====================================================================================
# --- Configuration ---
# ====================================================================================

# Validate that PATRONI_NAME is set, as it's critical for the default log path.
if [ -z "${PATRONI_NAME:-}" ]; then
  log_error "FATAL: PATRONI_NAME environment variable is not set. This sidecar cannot determine the default log path."
  exit 1
fi

# The sidecar mounts the parent data volume at a static location.
DATA_VOLUME_MOUNT_PATH="${DATA_VOLUME_MOUNT_PATH:-/data-volume}"

# Use the LOG_FILE_PATH from the environment if it exists, otherwise construct the default path dynamically.
LOG_FILE_PATH="${LOG_FILE_PATH:-${DATA_VOLUME_MOUNT_PATH}/${PATRONI_NAME}/pg_log/postgresql.json}"

# Read other settings from environment variables, with defaults.
LOGROTATE_CONF_PATH="${LOGROTATE_CONF_PATH:-/etc/logrotate.d/postgresql}"
LOGROTATE_STATE_FILE="${LOGROTATE_STATE_FILE:-/tmp/logrotate.status}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-10M}"
SHUTDOWN_GRACE_PERIOD="${SHUTDOWN_GRACE_PERIOD:-30}" # Seconds to wait before exiting
LOGROTATE_INTERVAL="${LOGROTATE_INTERVAL:-600}" # Seconds between logrotate checks

# ====================================================================================
# --- Main Logic ---
# ====================================================================================

log_msg "Starting log manager sidecar."
log_msg "Pod Name (PATRONI_NAME): ${PATRONI_NAME}"
log_msg "Log file to monitor: $LOG_FILE_PATH"
log_msg "Max log size: $LOG_MAX_SIZE"
log_msg "Rotation check interval: ${LOGROTATE_INTERVAL}s"
log_msg "Shutdown grace period: ${SHUTDOWN_GRACE_PERIOD}s"

# --- Generate the logrotate config on the fly ---
generate_logrotate_config "$LOG_FILE_PATH" "$LOGROTATE_CONF_PATH" "$LOG_MAX_SIZE"

# Wait for the log file to be created by PostgreSQL before starting.
log_msg "Waiting for log file to appear at $LOG_FILE_PATH..."
while [ ! -f "$LOG_FILE_PATH" ]; do
  sleep 2
done
log_msg "Log file found. Starting tail process in the background."

# Start tailing the log file in the background.
# Using -F is robust against file replacement/re-creation.
tail -F "$LOG_FILE_PATH" 2>/dev/null &
TAIL_PID=$!

# --- Graceful Shutdown Handler ---
# This function will be called when the container receives a shutdown signal.
cleanup() {
  log_msg "Received shutdown signal. Entering grace period of ${SHUTDOWN_GRACE_PERIOD}s to capture final logs..." "info"
  
  # Wait for a few seconds to allow the main container to finish logging.
  # The tail process continues to run during this time, streaming the logs.
  sleep "$SHUTDOWN_GRACE_PERIOD"
  
  log_msg "Grace period over. Stopping tail process." "info"
  # Now, kill the background tail process. Use kill -9 to ensure it dies.
  kill -9 $TAIL_PID || true # '|| true' prevents script exit if tail is already gone
  
  log_msg "Shutdown complete." "info"
  exit 0
}

# Trap the TERM signal (sent by 'docker stop' or Kubernetes) and call the cleanup function.
trap cleanup SIGTERM SIGINT

# --- Main Loop for Log Rotation ---
log_msg "Starting log rotation loop."
while true; do
  # Run logrotate with the specific config file and a state file in a writable location.
  logrotate -s "$LOGROTATE_STATE_FILE" "$LOGROTATE_CONF_PATH"
  
  # Wait for the configured interval before checking again.
  sleep "$LOGROTATE_INTERVAL" &
  # Wait for sleep to finish, but allow the trap to interrupt it.
  wait $!
done
