#!/bin/bash
# Provisionnement d'un serveur applicatif (role: app). Rejouable sans effet de bord.
# Variables attendues (passées par le Vagrantfile via env:) : DB_USER, DB_PASSWORD
# Optionnelles : DB_NAME (resultats), DB_PORT (5432)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${DB_USER:?DB_USER manquant}"
: "${DB_PASSWORD:?DB_PASSWORD manquant}"

# 1. Paquets : un seul apt-get, uniquement s'ils manquent (connexion lente)
if ! dpkg -s python3-psycopg2 python3-yaml >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq python3-psycopg2 python3-yaml curl
fi

# 2. Adresse de la base lue dans la source unique de vérité (aucune IP en dur)
DB_HOST=$(python3 - <<'PY'
import yaml
data = yaml.safe_load(open("/vagrant/config/noeuds.yml"))
noeuds = data["noeuds"] if isinstance(data, dict) else data
print(next(n["ip"] for n in noeuds if n["role"] == "bdd"))
PY
)

# 3. Fichier d'environnement : réécrit en entier à chaque fois (jamais de >>)
cat > /etc/resultats-bf.env <<EOF
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-resultats}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
APP_PORT=3000
EOF
chmod 600 /etc/resultats-bf.env

# 4. Code de l'application, copié hors du dossier synchronisé
install -d /opt/resultats-bf
install -m 755 /vagrant/app/app.py /opt/resultats-bf/app.py

# 5. Service systemd (fichier réécrit en entier)
cat > /etc/systemd/system/resultats-bf.service <<'EOF'
[Unit]
Description=Service RESULTATS-BF
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/resultats-bf.env
ExecStart=/usr/bin/python3 /opt/resultats-bf/app.py
Restart=always
RestartSec=1
DynamicUser=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable resultats-bf >/dev/null 2>&1
systemctl restart resultats-bf

# 6. Vérification : le service doit répondre sur /info (même si la base est absente)
for _ in $(seq 1 10); do
  if curl -fs http://127.0.0.1:3000/info >/dev/null; then
    echo "resultats-bf prêt sur $(hostname)"
    exit 0
  fi
  sleep 1
done
echo "ERREUR : le service ne répond pas sur /info" >&2
journalctl -u resultats-bf --no-pager -n 20 >&2
exit 1
