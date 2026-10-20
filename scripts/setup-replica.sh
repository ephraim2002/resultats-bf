#!/usr/bin/env bash
set -Eeuo pipefail

source /vagrant/scripts/common.sh

require_env REPL_PASSWORD

PRIMARY_IP="${DB_PRIMARY_IP:-192.168.63.31}"
export DEBIAN_FRONTEND=noninteractive

log "Installation de PostgreSQL sur la réplique"
apt-get update
apt-get install -y postgresql postgresql-client

PG_VERSION="$(ls /etc/postgresql | sort -V | tail -n 1)"
PG_DATA="/var/lib/postgresql/${PG_VERSION}/main"
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"

systemctl enable postgresql

if [[ -f "${PG_DATA}/standby.signal" ]]; then
    log "Une réplique existe déjà : conservation des données"
    systemctl restart postgresql
    exit 0
fi

log "Attente de la base primaire ${PRIMARY_IP}"
wait_for_postgres "$PRIMARY_IP" 5432 90

systemctl stop postgresql

log "Création de la copie initiale de la base"
rm -rf "${PG_DATA:?}/"*

install -o postgres -g postgres -m 700 -d "$PG_DATA"

sudo -u postgres env PGPASSWORD="$REPL_PASSWORD" \
    pg_basebackup \
    -h "$PRIMARY_IP" \
    -p 5432 \
    -U repli_user \
    -D "$PG_DATA" \
    -Fp -Xs -P -R

printf '%s:5432:replication:repli_user:%s\n' \
    "$PRIMARY_IP" "$REPL_PASSWORD" > /var/lib/postgresql/.pgpass
chown postgres:postgres /var/lib/postgresql/.pgpass
chmod 600 /var/lib/postgresql/.pgpass

chown -R postgres:postgres "$PG_DATA"
chmod 700 "$PG_DATA"

if grep -Eq "^[#[:space:]]*listen_addresses[[:space:]]*=" "$PG_CONF"; then
    sed -ri "s|^[#[:space:]]*listen_addresses[[:space:]]*=.*|listen_addresses = '*'|" "$PG_CONF"
else
    echo "listen_addresses = '*'" >> "$PG_CONF"
fi

systemctl start postgresql

for i in $(seq 1 60); do
    if sudo -u postgres psql -tAc \
        "SELECT pg_is_in_recovery()" | grep -q t; then
        log "La réplique est en mode standby"
        exit 0
    fi
    sleep 2
done

echo "La réplique n'est pas passée en mode standby." >&2
exit 1