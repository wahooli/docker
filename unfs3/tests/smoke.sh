#!/bin/sh
set -eu

unfsd -h 2>&1 | head -n 1

mkdir -p /tmp/share
echo '/tmp/share (rw,no_root_squash)' >/tmp/exports
rpcbind
unfsd -e /tmp/exports

i=0
until rpcinfo -p 127.0.0.1 2>/dev/null | grep -qE '100003 +3 +tcp'; do
  i=$((i + 1))
  [ "$i" -lt 20 ] || { echo "unfsd did not register with rpcbind" >&2; exit 1; }
  sleep 0.5
done

rpcinfo -p 127.0.0.1
rpcinfo -p 127.0.0.1 | grep -qE '100003 +3 +tcp'
rpcinfo -p 127.0.0.1 | grep -qE '100005 +3 +tcp'
echo "unfs3: ok"
