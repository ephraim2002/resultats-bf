#!/usr/bin/env bash
set -Eeuo pipefail

source /vagrant/scripts/common.sh

require_env DB_USER
require_env DB_PASSWORD

export DEBIAN_FRONTEND=noninteractive

log "Installation des dépendances Python"
apt-get update
apt-get install -y python3 python3-venv python3-pip python3-dev gcc libpq-dev curl

install -d -o vagrant -g vagrant /opt/resultats-bf
cp -a /vagrant/app/. /opt/resultats-bf/
python3 -m venv /opt/resultats-bf/venv
/opt/resultats-bf/venv/bin/pip install --upgrade pip
/opt/resultats-bf/venv/bin/pip install -r /opt/resultats-bf/requirements.txt

# L'adresse de la base primaire est fournie par le Vagrantfile.
DB_HOST="${DB_PRIMARY_IP:-192.168.63.31}"

cat > /etc/resultats-bf.env <<EOF
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-resultats}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
APP_PORT=5000
EOF
chmod 600 /etc/resultats-bf.env

cat > /etc/systemd/system/resultats-api.service <<'UNIT'
[Unit]
Description=API Resultats-BF
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=vagrant
Group=vagrant
WorkingDirectory=/opt/resultats-bf
EnvironmentFile=/etc/resultats-bf.env
ExecStart=/opt/resultats-bf/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:5000 --timeout 30 app:app
Restart=always
RestartSec=2
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
UNIT

chown -R vagrant:vagrant /opt/resultats-bf
systemctl daemon-reload
systemctl enable resultats-api
systemctl restart resultats-api

for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:5000/info >/dev/null; then
        log "API operationnelle sur le port 5000"
        exit 0
    fi
    sleep 2
done

journalctl -u resultats-api --no-pager -n 80 >&2
echo "ERREUR : l'API n'a pas démarré correctement sur le port 5000." >&2
exit 1
