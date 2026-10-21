#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== CONTROLE DE L'INFRASTRUCTURE RESULTATS-BF ==="

for ip in 192.168.63.21 192.168.63.22 192.168.63.23 192.168.63.24; do
    echo "--- Application ${ip} ---"
    curl --fail --silent --show-error "http://${ip}:5000/sante"
    echo
done

echo "--- Configuration HAProxy ---"
haproxy -c -f /etc/haproxy/haproxy.cfg

echo "--- Services ---"
systemctl is-active haproxy
systemctl is-active keepalived

echo "--- Adresse virtuelle ---"
ip -4 addr show | grep -F '192.168.63.10' || true

echo "=== CONTROLE TERMINE ==="