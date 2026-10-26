#!/usr/bin/env bash
# Modifie un paramètre de l'API puis redémarre le service. À lancer SUR un serveur app :
#   sudo bash /vagrant/scripts/app-config.sh DB_HOST 192.168.63.32
#   sudo bash /vagrant/scripts/app-config.sh CACHE_TTL 0      (0 désactive le cache)
set -euo pipefail
CLE="${1:?clé manquante}"; VAL="${2:?valeur manquante}"
case "$CLE" in DB_HOST|CACHE_TTL) ;; *) echo "clé non autorisée : $CLE" >&2; exit 1;; esac
F=/etc/resultats-bf.env
if grep -q "^$CLE=" "$F"; then sed -i "s|^$CLE=.*|$CLE=$VAL|" "$F"; else echo "$CLE=$VAL" >> "$F"; fi
systemctl restart resultats-api
echo "$(hostname) : $CLE=$VAL"
