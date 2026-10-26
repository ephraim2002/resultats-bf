#!/usr/bin/env bash
# =============================================================================
# scripts/switch-db-host.sh — Redirige l'API vers une autre base de données
# Propriétaire : Ingénieur données (étape manquante de la procédure de bascule)
#
# À lancer SUR CHAQUE SERVEUR APPLICATIF (app1, app2, ...) :
#   sudo bash /vagrant/scripts/switch-db-host.sh <IP_DE_LA_BASE>
#
# Idempotent : si l'API vise déjà cette adresse, il n'y a rien à faire.
# Attention : scripts/setup-app.sh réécrit DB_HOST (vers bdd1) à chaque
# "vagrant provision" des serveurs applicatifs. Après une bascule, il ne
# faut donc PAS rejouer ce provisionnement sans refaire cette étape.
# =============================================================================
set -Eeuo pipefail

ENV_FILE=/etc/resultats-bf.env
NEW_HOST="${1:-}"

if [[ -z "$NEW_HOST" ]]; then
    echo "Usage : sudo bash $0 <IP_DE_LA_BASE>" >&2
    exit 1
fi

if [[ ! "$NEW_HOST" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    echo "ERREUR : '$NEW_HOST' n'est pas une adresse IPv4." >&2
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERREUR : $ENV_FILE introuvable (serveur applicatif non provisionné ?)." >&2
    exit 1
fi

CURRENT="$(grep -E '^DB_HOST=' "$ENV_FILE" | cut -d= -f2 || true)"

if [[ "$CURRENT" == "$NEW_HOST" ]]; then
    echo "$(hostname) : DB_HOST vaut déjà ${NEW_HOST}, rien à faire."
    exit 0
fi

# On ne modifie QUE la ligne DB_HOST ; les autres variables restent intactes.
sed -i "s/^DB_HOST=.*/DB_HOST=${NEW_HOST}/" "$ENV_FILE"

# Le service lit ce fichier au démarrage : il faut le redémarrer.
systemctl restart resultats-api

for _ in $(seq 1 15); do
    if curl -fsS -o /dev/null http://127.0.0.1:5000/info; then
        echo "$(hostname) : DB_HOST ${CURRENT:-?} -> ${NEW_HOST}, API relancée."
        exit 0
    fi
    sleep 1
done

echo "ERREUR : l'API ne répond pas après le changement de DB_HOST." >&2
exit 1
