#!/usr/bin/env bash
# Commun à toutes les VM : paquets de base + résolution des noms (idempotent).
set -euo pipefail
cd /tmp
source /vagrant/scripts/lib.sh
installer python3-yaml

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
python3 - /vagrant/config/noeuds.yml > "$TMP" <<'PY'
import sys, yaml
for n in yaml.safe_load(open(sys.argv[1])):
    print(n["ip"], n["nom"])
PY
bloc_fichier /etc/hosts resultats-bf "$TMP" || true
