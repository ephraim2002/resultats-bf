#!/usr/bin/env bash
# Serveur applicatif sans état : API Flask derrière gunicorn, service systemd.
set -euo pipefail
cd /tmp
source /vagrant/scripts/lib.sh
: "${DB_NAME:?}" "${DB_USER:?}" "${DB_PASSWORD:?}" "${PRIMARY_IP:?}" "${REPLICA_IP:?}" "${REDIS_PASSWORD:?}"

installer python3-flask python3-psycopg2 python3-redis gunicorn
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHANGE=0

install -d -m 755 /opt/resultats-bf
if maj /opt/resultats-bf/app.py /vagrant/app/app.py; then CHANGE=1; fi

# DB_HOST et CACHE_TTL déjà présents sont conservés : un reprovisionnement ne doit
# pas défaire une bascule de base (idempotence).
ENVF=/etc/resultats-bf.env
cat > "$TMP/env" <<EOFE
DB_HOST=$(valeur_env "$ENVF" DB_HOST "$PRIMARY_IP")
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
REDIS_HOST=$REPLICA_IP
REDIS_PASSWORD=$REDIS_PASSWORD
CACHE_TTL=$(valeur_env "$ENVF" CACHE_TTL 60)
EOFE
if maj "$ENVF" "$TMP/env" 0600; then CHANGE=1; fi

cat > "$TMP/unit" <<'EOFU'
[Unit]
Description=API RESULTATS-BF
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/resultats-bf.env
WorkingDirectory=/opt/resultats-bf
ExecStart=/usr/bin/gunicorn --workers 2 --bind 0.0.0.0:3000 app:app
Restart=always
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOFU
if maj /etc/systemd/system/resultats-api.service "$TMP/unit"; then
  systemctl daemon-reload; CHANGE=1
fi
systemctl enable resultats-api >/dev/null 2>&1
if [ "$CHANGE" = 1 ] || ! systemctl is-active --quiet resultats-api; then
  systemctl restart resultats-api
fi
echo "[$(hostname)] API démarrée, DB_HOST=$(valeur_env "$ENVF" DB_HOST ?)"
