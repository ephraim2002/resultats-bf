#!/usr/bin/env bash
# bdd2 : réplique PostgreSQL en flux de bdd1, plus Redis (E3).
set -euo pipefail
cd /tmp
source /vagrant/scripts/lib.sh
: "${DB_NAME:?}" "${DB_USER:?}" "${REPL_USER:?}" "${REPL_PASSWORD:?}" "${REDIS_PASSWORD:?}" "${PRIMARY_IP:?}" "${NODE_IP:?}"

installer postgresql redis-server
PGV=$(pgv)
CONF=/etc/postgresql/$PGV/main
PGDATA=/var/lib/postgresql/$PGV/main
RESEAU_CIDR="${NODE_IP%.*}.0/24"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CHANGE=0

printf "listen_addresses = '*'\nhot_standby = on\npassword_encryption = scram-sha-256\n" > "$TMP/conf"
if maj "$CONF/conf.d/resultats.conf" "$TMP/conf"; then CHANGE=1; fi
cat > "$TMP/hba" <<EOFH
host    $DB_NAME       $DB_USER      $RESEAU_CIDR   scram-sha-256
host    replication    $REPL_USER    $RESEAU_CIDR   scram-sha-256
EOFH
if bloc_fichier "$CONF/pg_hba.conf" resultats-bf "$TMP/hba"; then CHANGE=1; fi

# Copie initiale depuis le primaire, une seule fois (standby.signal fait foi).
if [ ! -f "$PGDATA/standby.signal" ]; then
  attendre_pg "$PRIMARY_IP"
  systemctl stop postgresql
  find "$PGDATA" -mindepth 1 -delete
  sudo -u postgres env PGPASSWORD="$REPL_PASSWORD" "/usr/lib/postgresql/$PGV/bin/pg_basebackup" \
       -h "$PRIMARY_IP" -U "$REPL_USER" -D "$PGDATA" -R -X stream
  CHANGE=1
fi
systemctl enable postgresql >/dev/null 2>&1
if [ "$CHANGE" = 1 ] || ! systemctl is-active --quiet postgresql; then
  systemctl restart postgresql
fi

# E3 : Redis, protégé par mot de passe, accessible depuis le réseau privé seulement.
cat > "$TMP/redis" <<EOFR
bind 127.0.0.1 $NODE_IP
protected-mode yes
requirepass $REDIS_PASSWORD
maxmemory 64mb
maxmemory-policy allkeys-lru
EOFR
RCHANGE=0
if bloc_fichier /etc/redis/redis.conf resultats-bf "$TMP/redis"; then RCHANGE=1; fi
systemctl enable redis-server >/dev/null 2>&1
if [ "$RCHANGE" = 1 ] || ! systemctl is-active --quiet redis-server; then
  systemctl restart redis-server
fi
echo "[bdd2] en mode réplique : $(sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery();')"
