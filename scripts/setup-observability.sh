#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y prometheus curl ca-certificates gnupg apt-transport-https

# Installation du dépôt officiel Grafana.
install -d -m 755 /etc/apt/keyrings

curl -fsSL https://apt.grafana.com/gpg.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/grafana.gpg

chmod 644 /etc/apt/keyrings/grafana.gpg

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    > /etc/apt/sources.list.d/grafana.list

apt-get update
apt-get install -y grafana

# Configuration des cibles de collecte.
cat > /etc/prometheus/prometheus.yml <<'PROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["127.0.0.1:9090"]

  - job_name: node
    static_configs:
      - targets:
          - "192.168.63.31:9100"
          - "192.168.63.32:9100"
          - "192.168.63.21:9100"
          - "192.168.63.22:9100"
          - "192.168.63.23:9100"
          - "192.168.63.24:9100"
          - "192.168.63.11:9100"
          - "192.168.63.12:9100"
          - "192.168.63.41:9100"
PROM

# Collecter les métriques des deux load balancers.
cat /vagrant/rbf-observability-dashboard/prometheus/haproxy-scrape.yml \
    >> /etc/prometheus/prometheus.yml

# Source de données Grafana automatiquement provisionnée.
install -d -m 755 /etc/grafana/provisioning/datasources

cat > /etc/grafana/provisioning/datasources/prometheus.yml <<'GRAFANA'
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: true
GRAFANA

# Dashboard Grafana automatiquement provisionné.
install -d -o grafana -g grafana -m 755 /var/lib/grafana/dashboards
install -d -m 755 /etc/grafana/provisioning/dashboards
install -m 644 \
    /vagrant/rbf-observability-dashboard/grafana/dashboards/resultats-bf.json \
    /var/lib/grafana/dashboards/resultats-bf.json
install -m 644 \
    /vagrant/rbf-observability-dashboard/grafana/provisioning/dashboards/resultats-bf.yml \
    /etc/grafana/provisioning/dashboards/resultats-bf.yml
chown -R grafana:grafana /var/lib/grafana/dashboards

promtool check config /etc/prometheus/prometheus.yml

systemctl enable prometheus grafana-server
systemctl restart prometheus
systemctl restart grafana-server

for i in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:9090/-/ready >/dev/null &&
       curl -fsS http://127.0.0.1:3000/api/health >/dev/null; then
        echo "Prometheus et Grafana sont opérationnels."
        exit 0
    fi
    sleep 2
done

systemctl --no-pager --full status prometheus grafana-server || true
journalctl -u prometheus -u grafana-server --no-pager -n 80 || true
echo "Échec du démarrage de l'observabilité." >&2
exit 1