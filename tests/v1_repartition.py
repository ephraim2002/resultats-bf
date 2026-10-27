#!/usr/bin/env python3
"""Scénario V1 — Répartition : N appels successifs à /info, comptage par serveur.

Usage : python tests/v1_repartition.py [URL] [NB_APPELS] [NB_SERVEURS_ATTENDUS]
Exemple : python tests/v1_repartition.py http://localhost:8080 20 2
Critère du sujet : écart entre le serveur le plus et le moins sollicité < 20 %.
"""
import json
import sys
import urllib.request
from collections import Counter

url = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080").rstrip("/")
n = int(sys.argv[2]) if len(sys.argv) > 2 else 20
attendus = int(sys.argv[3]) if len(sys.argv) > 3 else 0

compte, erreurs = Counter(), 0
for i in range(1, n + 1):
    try:
        with urllib.request.urlopen(url + "/info", timeout=3) as rep:
            hote = json.load(rep)["hote"]
        compte[hote] += 1
        print(f"appel {i:3d} -> {hote}")
    except Exception as exc:                      # service injoignable, 503, JSON invalide...
        erreurs += 1
        print(f"appel {i:3d} -> ERREUR ({exc})")

print("\n--- Résultat brut ---")
for hote, nb in sorted(compte.items()):
    print(f"{hote:10s} {nb:3d} appels ({100 * nb / n:5.1f} %)")
print(f"erreurs    {erreurs:3d}")

volumes = list(compte.values()) + [0] * max(0, attendus - len(compte))
ecart = 100 * (max(volumes) - min(volumes)) / n if compte else 100.0
print(f"\nServeurs ayant répondu : {len(compte)}" + (f" sur {attendus} attendus" if attendus else ""))
print(f"Écart entre le plus et le moins sollicité : {ecart:.1f} % (critère : < 20 %)")

ok = erreurs == 0 and len(compte) >= 2 and ecart < 20
print("V1 :", "OK" if ok else "ECHEC")
sys.exit(0 if ok else 1)