#!/bin/sh
set -eu

openvpn --version | head -n 1
dnsmasq --version | head -n 1
haproxy -v | head -n 1
iptables -V
ip -V

iptables -V | grep -q nf_tables

cat >/tmp/dnsmasq.conf <<'EOF'
port=5353
no-resolv
no-hosts
address=/example.test/10.0.0.1
EOF
dnsmasq --test --conf-file=/tmp/dnsmasq.conf

cat >/tmp/haproxy.cfg <<'EOF'
defaults
  mode tcp
  timeout connect 5s
  timeout client 1m
  timeout server 1m
frontend https
  bind :8443
  default_backend upstream
backend upstream
  server upstream 127.0.0.1:443
EOF
haproxy -c -f /tmp/haproxy.cfg

openvpn --genkey tls-crypt /tmp/tls-crypt.key
grep -q 'BEGIN OpenVPN Static key V1' /tmp/tls-crypt.key

echo "openvpn: ok"
