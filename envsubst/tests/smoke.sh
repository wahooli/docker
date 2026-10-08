#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

[ "$(id -u)" = "65534" ]

export SOURCE_DIR=/tmp/src DEST_DIR=/tmp/dest
mkdir -p "$SOURCE_DIR" "$DEST_DIR"
printf 'host=${DB_HOST}\nkeep=${KEEP}\n' >"$SOURCE_DIR/app.conf"
printf 'echo hello\n' >"$SOURCE_DIR/run.sh"

DB_HOST=db KEEP=replaced REPLACE_VARS='$DB_HOST' /docker-entrypoint.sh

grep -qx 'host=db' "$DEST_DIR/app.conf"
grep -qx 'keep=${KEEP}' "$DEST_DIR/app.conf"
[ -x "$DEST_DIR/run.sh" ]
echo "envsubst: ok"
