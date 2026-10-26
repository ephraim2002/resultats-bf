# Journal de bord - architecte réseau et répartition

Extrait du livrable L3. Compléter les dates et les difficultés réellement rencontrées.

## Décisions et raisons

| Date | Décision | Pourquoi |
|---|---|---|
| à compléter | Réseau privé 192.168.63.0/24, VIP 192.168.63.10 | Valeurs déjà présentes sur `main`, reprises dans la documentation |
| à compléter | HAProxy en round-robin, sonde `/sante` | Serveurs sans état ; retrait automatique d'un serveur défaillant (R4) |
| à compléter | Keepalived, lb1 priorité 110 et lb2 priorité 100 | Extension E1 : VIP partagée, service maintenu si lb1 tombe |
| à compléter | Configuration par `.env` (`NB_APP`, `ENABLE_HA`, secrets) | R3 et R7 : `.env.exemple` versionné, `.env` ignoré par Git |
| à compléter | Scripts de mesure V1, V2 et V6 en PowerShell dans `tests/reseau/` | Mesures reproductibles, résultats bruts conservés en CSV |

## Difficultés et solutions

| Difficulté | Solution |
|---|---|
| Deux implémentations du répartiteur en parallèle (la mienne et celle de `main`) | Ne garder que celle de `main` ; adapter la documentation et les tests à ses valeurs |
| Plage d'adresses 192.168.63.0/24 : elle correspond au groupe 8 d'après le sujet | À confirmer avec l'équipe et l'enseignant |
| Erreur « fichier .env manquant » au premier démarrage | Créer le `.env` par `Copy-Item .env.exemple .env` à la racine du dépôt |
| À compléter | À compléter |
