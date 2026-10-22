#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y prometheus-node-exporter

systemctl enable --now prometheus-node-exporter

curl -fsS http://127.0.0.1:9100/metrics >/dev/null

echo "Node Exporter opérationnel sur le port 9100."