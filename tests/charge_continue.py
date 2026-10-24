#!/usr/bin/env python3
"""Charge continue : des requêtes /resultat en boucle, avec comptage des erreurs seconde par seconde.

Usage : python tests/charge_continue.py [URL] [DUREE_SECONDES] [NB_THREADS]
Exemple : python tests/charge_continue.py http://localhost:8080 120 10

Sert à la démonstration E4 : on la lance, puis on exécute scripts/deploy_rolling.py dans une autre
fenêtre. Critère du sujet : une mise à jour complète sans une seule requête en erreur.
"""
import random
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import Counter

url = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080").rstrip("/")
duree = int(sys.argv[2]) if len(sys.argv) > 2 else 60
nb_threads = int(sys.argv[3]) if len(sys.argv) > 3 else 10

verrou = threading.Lock()
par_seconde = {}                      # seconde -> Counter des codes HTTP ("ERR" si pas de réponse)
debut = time.time()
fin = debut + duree


def boucle():
    while time.time() < fin:
        matricule = f"BF{random.randint(1, 50000):06d}"
        try:
            with urllib.request.urlopen(f"{url}/resultat?matricule={matricule}", timeout=5) as rep:
                code = str(rep.status)
        except urllib.error.HTTPError as exc:
            code = str(exc.code)
        except Exception:
            code = "ERR"
        with verrou:
            par_seconde.setdefault(int(time.time() - debut), Counter())[code] += 1


fils = [threading.Thread(target=boucle) for _ in range(nb_threads)]
for f in fils:
    f.start()
print(f"Charge : {nb_threads} threads pendant {duree} s sur {url} ...", flush=True)
for f in fils:
    f.join()

total = Counter()
print("\nseconde  requêtes  erreurs")
for s in sorted(par_seconde):
    c = par_seconde[s]
    erreurs = sum(nb for code, nb in c.items() if code != "200")
    total.update(c)
    if erreurs:                       # on n'affiche que les secondes dégradées
        print(f"{s:7d}  {sum(c.values()):8d}  {erreurs:7d}   {dict(c)}")

n_total = sum(total.values())
n_err = n_total - total["200"]
print(f"\nTotal : {n_total} requêtes, {total['200']} en 200, {n_err} en erreur ({dict(total)})")
print("Débit moyen :", round(n_total / duree, 1), "req/s")
print("RESULTAT :", "OK, aucune requête en erreur" if n_err == 0 else "ECHEC, des requêtes ont échoué")
sys.exit(0 if n_err == 0 else 1)