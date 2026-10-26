#!/usr/bin/env bash
# Fonctions communes, chargées par les autres scripts (source).

# installer PAQUET... : une seule installation groupée, seulement des paquets manquants.
installer() {
  local manquants="" p
  for p in "$@"; do dpkg -s "$p" >/dev/null 2>&1 || manquants="$manquants $p"; done
  if [ -n "$manquants" ]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $manquants
  fi
}

# maj DEST SOURCE [MODE] : copie SOURCE vers DEST si le contenu diffère.
# Retour 0 = modifié, 1 = inchangé.
maj() {
  if [ -f "$1" ] && cmp -s "$2" "$1"; then return 1; fi
  install -m "${3:-0644}" "$2" "$1"
}

# bloc_fichier FICHIER MARQUEUR SOURCE : remplace (ou ajoute) en fin de fichier le bloc
# encadré par "# BEGIN MARQUEUR" / "# END MARQUEUR". Jamais de doublon.
# Retour 0 = modifié, 1 = inchangé.
bloc_fichier() {
  local rc=0
  python3 - "$1" "$2" "$3" <<'PY' || rc=$?
import re, sys
f, m, src = sys.argv[1:4]
deb, fin = "# BEGIN " + m, "# END " + m
txt = open(f).read()
base = re.sub(re.escape(deb) + r".*?" + re.escape(fin) + r"\n?", "", txt, flags=re.S).rstrip("\n")
nouveau = base + "\n" + deb + "\n" + open(src).read().rstrip("\n") + "\n" + fin + "\n"
if nouveau != txt:
    open(f, "w").write(nouveau)
    sys.exit(10)
PY
  if [ "$rc" != 0 ] && [ "$rc" != 10 ]; then echo "bloc_fichier: échec sur $1" >&2; exit 1; fi
  [ "$rc" = 10 ]
}

# valeur_env FICHIER CLE DEFAUT : lit CLE=valeur dans un fichier d'environnement.
valeur_env() {
  local v
  v=$( { grep -s "^$2=" "$1" || true; } | head -n1 | cut -d= -f2- )
  echo "${v:-$3}"
}

pgv() { ls /usr/lib/postgresql | sort -V | tail -n1; }

attendre_pg() { # attendre_pg [HOTE]
  local i
  for i in $(seq 1 60); do
    pg_isready -q -h "${1:-127.0.0.1}" -p 5432 && return 0
    sleep 2
  done
  echo "PostgreSQL injoignable sur ${1:-127.0.0.1}" >&2
  return 1
}
