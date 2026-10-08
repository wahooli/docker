#!/bin/bash
set -euo pipefail

haproxy -v | head -n 1
redis-cli --version
[ "$(id -u):$(id -g)" = "99:99" ]

cat >/tmp/haproxy.cfg <<'EOF'
defaults
  mode tcp
  timeout connect 1s
  timeout client 1s
  timeout server 1s

frontend redis
  bind 127.0.0.1:6379
  default_backend redis_servers

backend redis_servers
  server redis-0 127.0.0.1:16379 check
EOF
haproxy -c -f /tmp/haproxy.cfg
