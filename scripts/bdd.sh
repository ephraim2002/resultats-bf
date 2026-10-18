#!/usr/bin/env bash
# =============================================================================
# scripts/bdd.sh — Provisionnement de bdd1 (base de données PRIMAIRE)
# Propriétaire : Ingénieur données
#
# Ce script est IDEMPOTENT : on peut le rejouer autant de fois qu'on veut
# (vagrant provision), le résultat est toujours le même, sans doublon.
# =============================================================================
set -euo pipefail                 # arrêt immédiat à la première erreur
export DEBIAN_FRONTEND=noninteractive   # apt ne pose aucune question

# -----------------------------------------------------------------------------
# 1. Lire les secrets depuis /vagrant/.env (fichier NON versionné dans Git)
#    /vagrant = le dossier du projet sur ton PC, vu depuis la VM.
#    `tr -d '\r'` retire les fins de ligne Windows (CRLF) qui casseraient tout.
# -----------------------------------------------------------------------------
ENV_FILE=/vagrant/.env
if [ ! -f "$ENV_FILE" ]; then
  echo "ERREUR : $ENV_FILE introuvable. Copie .env.exemple en .env puis remplis-le." >&2
  exit 1
fi
set -a                            # toute variable lue devient une variable d'environnement
# shellcheck disable=SC1090
source <(tr -d '\r' < "$ENV_FILE")
set +a

: "${DB_NAME:?DB_NAME manquante dans .env}"
: "${DB_USER:?DB_USER manquante dans .env}"
: "${DB_PASSWORD:?DB_PASSWORD manquante dans .env}"

# -----------------------------------------------------------------------------
# 2. Installer PostgreSQL (une seule commande groupée : connexion lente !)
# -----------------------------------------------------------------------------
apt-get update -qq
apt-get install -y -qq postgresql

PG_VER="$(ls /etc/postgresql | sort -V | tail -1)"   # ex. 16 sur Ubuntu 24.04
PG_CONF_DIR="/etc/postgresql/${PG_VER}/main"

# -----------------------------------------------------------------------------
# 3. Trouver notre adresse sur le réseau privé (sans l'écrire en dur)
#    La carte NAT de Vagrant est en 10.0.2.x ; la carte privée est en
#    192.168.56.x à 192.168.63.x (plage autorisée par VirtualBox).
# -----------------------------------------------------------------------------
PRIV_IP="$(ip -4 -o addr show | awk '{print $4}' \
  | grep -E '^192\.168\.(5[6-9]|6[0-3])\.' | head -1 | cut -d/ -f1)"
if [ -z "$PRIV_IP" ]; then
  echo "ERREUR : adresse du réseau privé introuvable." >&2
  exit 1
fi
SUBNET="${PRIV_IP%.*}.0/24"       # 192.168.X.31 -> 192.168.X.0/24

# -----------------------------------------------------------------------------
# 4. Écrire la configuration — on réécrit le fichier ENTIER (jamais de >>),
#    et on ne touche à rien (ni redémarrage) si le contenu est déjà bon.
# -----------------------------------------------------------------------------
CHANGED=0
write_if_changed() {              # usage : write_if_changed <fichier> <droits> < contenu
  local dest="$1" mode="$2" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ ! -f "$dest" ] || ! cmp -s "$tmp" "$dest"; then
    install -o postgres -g postgres -m "$mode" "$tmp" "$dest"
    CHANGED=1
  fi
  rm -f "$tmp"
}

# 4a. postgresql.conf : on dépose un fichier à nous dans conf.d/
#     listen_addresses='*' : écouter sur TOUTES les interfaces (piège n°1 :
#     par défaut PostgreSQL n'écoute que sur 127.0.0.1, donc injoignable).
write_if_changed "${PG_CONF_DIR}/conf.d/99-resultats-bf.conf" 644 <<'EOF'
# Géré par scripts/bdd.sh — ne pas modifier à la main
listen_addresses = '*'
# Préparation de la réplication (semaine 3)
wal_level = replica
max_wal_senders = 10
EOF

# 4b. pg_hba.conf : qui a le droit de se connecter, et comment.
#     Ici : seulement le sous-réseau privé du groupe, avec mot de passe.
write_if_changed "${PG_CONF_DIR}/pg_hba.conf" 640 <<EOF
# Géré par scripts/bdd.sh — ne pas modifier à la main
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
host    ${DB_NAME}      ${DB_USER}      ${SUBNET}               scram-sha-256
EOF

# -----------------------------------------------------------------------------
# 5. Démarrer / redémarrer PostgreSQL uniquement si nécessaire
# -----------------------------------------------------------------------------
systemctl enable postgresql >/dev/null 2>&1
if [ "$CHANGED" = 1 ]; then
  systemctl restart postgresql
else
  systemctl start postgresql
fi

for _ in $(seq 1 30); do
  pg_isready -q && break
  sleep 1
done
pg_isready -q || { echo "ERREUR : PostgreSQL ne répond pas." >&2; exit 1; }

# -----------------------------------------------------------------------------
# 6. Créer l'utilisateur, la base, la table, puis les 50 000 lignes
#    Les commandes SQL sont lancées en tant qu'utilisateur « postgres ».
#    `\gexec` exécute le texte produit par le SELECT : c'est le moyen d'écrire
#    « crée si n'existe pas » proprement (format %I / %L protège les valeurs).
# -----------------------------------------------------------------------------
cd /tmp
run_psql() { sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 "$@"; }

run_psql -v u="$DB_USER" -v p="$DB_PASSWORD" -v d="$DB_NAME" <<'SQL'
-- Utilisateur : créé s'il n'existe pas ; mot de passe toujours aligné sur .env
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'u', :'p')
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'u') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'u', :'p') \gexec
-- Base : créée si elle n'existe pas
SELECT format('CREATE DATABASE %I OWNER %I', :'d', :'u')
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'d') \gexec
SQL

run_psql -d "$DB_NAME" -v owner="$DB_USER" <<'SQL'
CREATE TABLE IF NOT EXISTS resultats (
  matricule varchar(12) PRIMARY KEY,
  nom       text         NOT NULL,
  serie     varchar(2)   NOT NULL,
  moyenne   numeric(4,2) NOT NULL,
  admis     boolean      NOT NULL
);
SELECT format('ALTER TABLE resultats OWNER TO %I', :'owner') \gexec

-- 50 000 lignes générées, UNIQUEMENT si la table est vide (idempotence)
INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT 'BF' || lpad(g::text, 6, '0'),
       'Candidat ' || g,
       (ARRAY['A','C','D','E','F'])[1 + (g % 5)],
       m,
       m >= 10
FROM (SELECT g, round((random() * 20)::numeric, 2) AS m
      FROM generate_series(1, 50000) AS g) AS t
WHERE NOT EXISTS (SELECT 1 FROM resultats);
SQL

# -----------------------------------------------------------------------------
# 7. Vérification : on se connecte en TCP avec le mot de passe, comme le
#    fera l'application.
# -----------------------------------------------------------------------------
NB="$(PGPASSWORD="$DB_PASSWORD" psql -X -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" \
      -tAc 'SELECT count(*) FROM resultats')"
echo "bdd1 prête : ${NB} lignes dans resultats, écoute sur ${PRIV_IP}:5432"
