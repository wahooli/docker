#!/bin/sh
set -eu

if [ ! -c /dev/net/tun ]; then
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200
  chmod 600 /dev/net/tun
fi

for f in /docker-entrypoint.d/*.sh; do
  [ -r "$f" ] || continue
  echo "docker-entrypoint.sh: running $f"
  sh "$f"
done

exec "$@"
