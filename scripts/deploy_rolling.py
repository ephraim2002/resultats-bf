#!/usr/bin/env python3
"""E4 — Déploiement sans coupure : met à jour les serveurs applicatifs un par un.

Usage (depuis la racine du dépôt) : python scripts/deploy_rolling.py [PAUSE_SECONDES]

Pour chaque serveur de rôle "app" de config/noeuds.yml, dans l'ordre :
  1. vagrant provision <nom> : copie la nouvelle app.py et redémarre le service en douceur
     (pendant le drainage, /sante renvoie 503 : le répartiteur écarte le serveur, qui continue
     de servir ses requêtes en cours, puis s'arrête et redémarre sur la nouvelle version) ;
  2. attend que /sante réponde 200 ;
  3. patiente PAUSE secondes (5 par défaut) pour que le répartiteur réintègre le serveur
     avant de passer au suivant : il reste toujours au moins un serveur disponible.
"""
import os
import re
import subprocess
import sys
import time
import urllib.request

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def serveurs_app():
    """Lit config/noeuds.yml (liste engendrée par le Vagrantfile) et garde les serveurs app."""
    with open(os.path.join(RACINE, "config", "noeuds.yml"), encoding="utf-8") as f:
        texte = f.read()
    blocs = re.split(r"^- ", texte, flags=re.M)[1:]
    noeuds = [dict(re.findall(r"^\s*(\w+):\s*(\S+)", b, re.M)) for b in blocs]
    return [n for n in noeuds if n.get("role") == "app"]


def sante_ok(ip):
    try:
        with urllib.request.urlopen(f"http://{ip}:3000/sante", timeout=2) as rep:
            return rep.status == 200
    except Exception:
        return False


def main():
    pause = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    noeuds = serveurs_app()
    if len(noeuds) < 2:
        sys.exit("Il faut au moins 2 serveurs applicatifs pour une mise à jour sans coupure.")
    debut = time.time()
    for n in noeuds:
        print(f"\n== {n['nom']} ({n['ip']}) : mise à jour", flush=True)
        t0 = time.time()
        if subprocess.run(["vagrant", "provision", n["nom"]], cwd=RACINE).returncode != 0:
            sys.exit(f"ECHEC : vagrant provision {n['nom']}. Les serveurs suivants n'ont pas été touchés.")
        limite = time.time() + 120
        while not sante_ok(n["ip"]):
            if time.time() > limite:
                sys.exit(f"ECHEC : {n['nom']} ne répond pas 200 sur /sante après 120 s.")
            time.sleep(1)
        print(f"{n['nom']} prêt en {time.time() - t0:.0f} s, pause {pause} s", flush=True)
        time.sleep(pause)
    print(f"\nDéploiement terminé : {len(noeuds)} serveurs en {time.time() - debut:.0f} s.")


if __name__ == "__main__":
    main()