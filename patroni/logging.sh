#!/bin/bash

# ====================================================================================
# --- Shared Logging Library ---
# ====================================================================================
# This script should be sourced by other scripts to provide logging functions.
# It respects the LOG_FORMAT environment variable.
# Set LOG_FORMAT=json to enable structured JSON logging.

# Default to plain text logging if LOG_FORMAT is not set.
LOG_FORMAT="${LOG_FORMAT:-plain}"

# The main logging function.
# Usage: log_msg "<message>" [level]
# Example:
#   log_msg "Starting the process..."
#   log_msg "Debugging connection." "debug"
#   log_msg "Something is not right" "WARNING"
log_msg() {
  local message="$1"
  # First, get the second argument with a default of 'info'. This is safe with 'set -u'.
  local level_raw="${2:-info}"
  # Then, convert the result to lowercase.
  local level="${level_raw,,}"
  
  # Default SCRIPT_NAME if not set by the calling script.
  local script_name="${SCRIPT_NAME:-unknown_script}"

  # --- Validate the log level ---
  local valid_levels=" critical error warning info debug trace "
  # Note: The spaces around the string and the variable are important for an exact word match.
  if ! [[ "$valid_levels" =~ " $level " ]]; then
    # If an invalid level is used, log a warning and default to 'info'.
    # We call the function recursively with a valid level to report the error.
    log_msg "Invalid log level '$level' provided. Defaulting to 'info'." "warning"
    level="info"
  fi

  if [ "$LOG_FORMAT" = "json" ]; then
    # Use jq with the -c (compact) flag to ensure single-line output.
    # The timestamp now includes milliseconds (%3N) for better ISO 8601 compatibility.
    jq -c -n \
      --arg ts "$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')" \
      --arg level "$level" \
      --arg script "$script_name" \
      --arg message "$message" \
      '{ts: $ts, level: $level, script: $script, message: $message}'
  else
    # Plain text format
    echo "[${script_name}] [$(echo "$level" | tr '[:lower:]' '[:upper:]')] ${message}"
  fi
}

# Convenience function for logging errors to stderr.
# Usage: log_error "<error_message>"
log_error() {
  log_msg "$1" "error" >&2
}

# --- Logrotate Configuration Generator ---
# Creates a logrotate configuration file dynamically.
# Usage: generate_logrotate_config <log_file_to_rotate> <config_output_path> <max_size>
generate_logrotate_config() {
  local log_file_to_rotate="$1"
  local config_output_path="$2"
  local max_size="$3"

  log_msg "Generating logrotate configuration at '$config_output_path'..."

  # Create the configuration content.
  # - rotate 0: Rotated logs are removed immediately.
  # - copytruncate: Safely rotates the file without interrupting tail.
  cat > "$config_output_path" <<EOF
$log_file_to_rotate {
    size $max_size
    rotate 0
    copytruncate
    notifempty
    missingok
}
EOF
  log_msg "Logrotate configuration generated successfully."
}
