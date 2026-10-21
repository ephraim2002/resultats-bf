#!/usr/bin/env bash
set -Eeuo pipefail

echo "ATTENTION : ce script promeut bdd2 en nouvelle base primaire."
echo "Il ne bascule pas automatiquement les applications ni bdd1."
read -r -p "Pour confirmer, saisir PROMOUVOIR-BDD2 : " confirmation

if [[ "$confirmation" != "PROMOUVOIR-BDD2" ]]; then
    echo "Opération annulée."
    exit 1
fi

is_replica="$(sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery();' | tr -d '[:space:]')"

if [[ "$is_replica" != "t" ]]; then
    echo "ERREUR : ce serveur n'est pas une réplique en récupération."
    exit 1
fi

sudo -u postgres psql -v ON_ERROR_STOP=1 -c 'SELECT pg_promote();'

for i in $(seq 1 30); do
    state="$(sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery();' | tr -d '[:space:]')"
    if [[ "$state" == "f" ]]; then
        echo "Promotion réussie : ce serveur est maintenant primaire."
        echo "Vérifier les données, puis mettre à jour DB_HOST sur app1 et app2."
        exit 0
    fi
    sleep 2
done

echo "ERREUR : la promotion n'a pas été confirmée." >&2
exit 1