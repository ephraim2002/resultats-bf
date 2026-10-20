#!/usr/bin/env bash
set -Eeuo pipefail

source /vagrant/scripts/common.sh

require_env DB_PASSWORD
require_env REPL_PASSWORD

if [[ "DB_PASSWORD" == "$DB_PASSWORD" ||
      "REPL_PASSWORD" == "$REPL_PASSWORD" ]]; then
    echo "Remplace les mots de passe d'exemple dans $DB_PASSWORD .env avant le provisionnement $REPL_PASSWORD." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
log "Installation de PostgreSQL"
apt-get update
apt-get install -y postgresql postgresql-contrib

PG_VERSION="$(ls /etc/postgresql | sort -V | tail -n 1)"
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

set_pg_setting() {
    local key="$1"
    local value="$2"
    if grep -Eq "^[#[:space:]]*${key}[[:space:]]*=" "$PG_CONF"; then
        sed -ri "s|^[#[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$PG_CONF"
    else
        printf '\n%s = %s\n' "$key" "$value" >> "$PG_CONF"
    fi
}

set_pg_setting "listen_addresses" "'*'"
set_pg_setting "wal_level" "replica"
set_pg_setting "max_wal_senders" "10"
set_pg_setting "max_replication_slots" "10"

if ! grep -q "RESULTATS-BF MANAGED ACCESS" "$PG_HBA"; then
    cat >> "$PG_HBA" <<'HBA'

# RESULTATS-BF MANAGED ACCESS
host    resultats    resultats_app    192.168.63.0/24    scram-sha-256
host    replication  repli_user       192.168.63.0/24    scram-sha-256
HBA
fi

systemctl enable postgresql
systemctl restart postgresql

log "Création des rôles PostgreSQL"
sudo -u postgres psql \
    -v app_password="$DB_PASSWORD" \
    -v repl_password="$REPL_PASSWORD" <<'SQL'
DO $$
BEGIN
    CREATE ROLE resultats_app LOGIN;
EXCEPTION WHEN duplicate_object THEN
    NULL;
END
$$;

DO $$
BEGIN
    CREATE ROLE repli_user LOGIN REPLICATION;
EXCEPTION WHEN duplicate_object THEN
    NULL;
END
$$;

ALTER ROLE resultats_app
    WITH LOGIN PASSWORD :'app_password';

ALTER ROLE repli_user
    WITH LOGIN REPLICATION PASSWORD :'repl_password';
SQL

if ! sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname = 'resultats'" | grep -q 1; then
    sudo -u postgres createdb resultats
fi

log "Chargement du schéma et des données"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d resultats \
    -f /vagrant/database/schema.sql

sudo -u postgres psql -v ON_ERROR_STOP=1 -d resultats \
    -f /vagrant/database/seed.sql

sudo -u postgres psql -v ON_ERROR_STOP=1 -d resultats <<'SQL'
GRANT CONNECT ON DATABASE resultats TO resultats_app;
GRANT USAGE ON SCHEMA public TO resultats_app;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO resultats_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO resultats_app;
SQL

systemctl restart postgresql
log "Base primaire prête"
sudo -u postgres psql -d resultats -c \
    "SELECT COUNT(*) AS nombre_resultats FROM resultats;"