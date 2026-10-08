#!/bin/bash
set -euo pipefail

[ "$(id -u)" = "65534" ]

nc -l 127.0.0.1 18080 &
wait-for-it.sh 127.0.0.1:18080 -t 5 -- echo "open port: ok"

if wait-for-it.sh 127.0.0.1:18081 -t 1 -q; then
  echo "closed port reported as open" >&2
  exit 1
fi
echo "closed port: ok"
