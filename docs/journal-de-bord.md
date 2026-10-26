# Journal de bord - groupe 18

Livrable L3. À compléter avec les dates, les personnes et les difficultés réellement
rencontrées.

## Répartition des rôles

| Rôle | Responsable | Périmètre |
|---|---|---|
| Architecte réseau et répartition | à compléter | Plan d'adressage, Vagrantfile, HAProxy, sonde, E1 |
| Ingénieur applicatif | à compléter | API, absence d'état, erreurs de base |
| Ingénieur données | à compléter | PostgreSQL, jeu de données, réplication, bascule, E3 |
| Ingénieur essais | à compléter | Scénarios V1 à V6, mesures, rédaction |

## Décisions

| Date | Décision | Pourquoi |
|---|---|---|
| à compléter | Réseau 192.168.63.0/24 | Numéro de groupe du TP : 8 (X = 55 + 8), dans la plage autorisée par VirtualBox |
| à compléter | Table `NOEUDS` comme source unique | R3 : HAProxy suit `NB_APP` sans adresse en dur |
| à compléter | HAProxy, sonde `/sante`, keepalived en unicast | R4 et E1 |
| à compléter | PostgreSQL en réplication en flux, secrets dans `.env` | R5 et R7 |
| à compléter | Redis sur bdd2 (E3) | Cache indépendant de la panne de bdd1 |
| à compléter | Scénarios de test en PowerShell | Mesures reproductibles, résultats bruts conservés |

## Difficultés rencontrées

| Difficulté | Solution |
|---|---|
| À compléter | À compléter |
