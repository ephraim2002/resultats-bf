#!/usr/bin/env bash
# usage : sudo bash test-replication.sh inserer|lire MATRICULE [BASE]
cd /tmp
BASE="${3:-resultats}"
case "${1:-}" in
  inserer) sudo -u postgres psql -d "$BASE" -qc "INSERT INTO resultats VALUES ('$2','Test replication','H',12.50,true) ON CONFLICT DO NOTHING;" && echo "inséré : $2" ;;
  lire)    sudo -u postgres psql -d "$BASE" -tAc "SELECT matricule || ' ' || nom FROM resultats WHERE matricule = '$2';" ;;
  *) echo "usage : $0 inserer|lire MATRICULE [BASE]" >&2; exit 1 ;;
esac
