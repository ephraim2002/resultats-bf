#!/usr/bin/env bash
# Promotion de la réplique bdd2 en primaire. À lancer SUR bdd2 :
#   sudo bash /vagrant/scripts/bascule-bdd.sh
# Les serveurs applicatifs doivent ensuite pointer vers bdd2 (scripts/app-config.sh).
set -euo pipefail
cd /tmp
EN_REPLIQUE=$(sudo -u postgres psql -tAc "SELECT pg_is_in_recovery();")
if [ "$EN_REPLIQUE" != "t" ]; then
  echo "bdd2 n'est pas en mode réplique (déjà promue ?)"; exit 0
fi
sudo -u postgres psql -tAc "SELECT pg_promote(wait => true, wait_seconds => 30);" >/dev/null
echo "bdd2 promue, en mode réplique : $(sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery();')"
