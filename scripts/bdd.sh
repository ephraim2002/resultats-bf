#!/usr/bin/env bash
# bdd1 : PostgreSQL primaire (lecture/écriture), base, utilisateurs, jeu de données.
set -euo pipefail
cd /tmp
source /vagrant/scripts/lib.sh
: "${DB_NAME:?DB_NAME manquant dans .env}" "${DB_USER:?}" "${DB_PASSWORD:?}" "${REPL_USER:?}" "${REPL_PASSWORD:?}" "${NODE_IP:?}"

installer postgresql
PGV=$(pgv)
CONF=/etc/postgresql/$PGV/main
RESEAU_CIDR="${NODE_IP%.*}.0/24"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHANGE=0

# Écoute sur toutes les interfaces (piège n°1) ; le répertoire de données reste local.
cat > "$TMP/conf" <<EOFC
listen_addresses = '*'
wal_level = replica
max_wal_senders = 5
wal_keep_size = 256MB
hot_standby = on
password_encryption = scram-sha-256
EOFC
if maj "$CONF/conf.d/resultats.conf" "$TMP/conf"; then CHANGE=1; fi

cat > "$TMP/hba" <<EOFH
host    $DB_NAME       $DB_USER      $RESEAU_CIDR   scram-sha-256
host    replication    $REPL_USER    $RESEAU_CIDR   scram-sha-256
EOFH
if bloc_fichier "$CONF/pg_hba.conf" resultats-bf "$TMP/hba"; then CHANGE=1; fi

systemctl enable postgresql >/dev/null 2>&1
if [ "$CHANGE" = 1 ] || ! systemctl is-active --quiet postgresql; then
  systemctl restart postgresql
fi
attendre_pg 127.0.0.1

PSQL=(sudo -u postgres psql -v ON_ERROR_STOP=1 -q)
"${PSQL[@]}" -v dbname="$DB_NAME" -v dbuser="$DB_USER" -v dbpw="$DB_PASSWORD" \
             -v repuser="$REPL_USER" -v reppw="$REPL_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'dbuser')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'dbuser') \gexec
ALTER ROLE :"dbuser" PASSWORD :'dbpw';
SELECT format('CREATE ROLE %I LOGIN REPLICATION', :'repuser')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'repuser') \gexec
ALTER ROLE :"repuser" PASSWORD :'reppw';
SELECT format('CREATE DATABASE %I', :'dbname')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'dbname') \gexec
SQL

"${PSQL[@]}" -d "$DB_NAME" -f /vagrant/database/schema.sql
"${PSQL[@]}" -d "$DB_NAME" -f /vagrant/database/seed.sql
"${PSQL[@]}" -d "$DB_NAME" -v dbuser="$DB_USER" <<'SQL'
GRANT SELECT ON resultats TO :"dbuser";
SQL
echo "[bdd1] lignes dans resultats : $(sudo -u postgres psql -d "$DB_NAME" -tAc 'SELECT count(*) FROM resultats;')"
