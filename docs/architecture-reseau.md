# Architecte réseau et répartition

Partie du dossier d'architecture (livrable L2) et notes d'exploitation du rôle 1.
Schéma : `docs/architecture.svg`. Les chiffres de la section 5 sont à relever avec les
scripts de `tests/reseau/` : aucun résultat n'est écrit ici à l'avance. Les points marqués
« à confirmer » sont à vérifier dans le code du dépôt avant la remise.

## 1. Périmètre

Plan d'adressage, répartiteur HAProxy, sonde de santé, extension E1 (répartiteur
redondant avec Keepalived). Fichiers concernés : `Vagrantfile`, `scripts/setup-lb.sh`,
`scripts/setup-lb-ha.sh`, `.env.exemple`.

## 2. Plan d'adressage

Réseau privé hôte-seul : `192.168.63.0/24`.

| Machine | Rôle | Adresse | Statut |
|---|---|---|---|
| (VIP) | IP virtuelle VRRP | 192.168.63.10 | E1 |
| lb1 | Répartiteur actif, priorité VRRP 110 | 192.168.63.11 | Obligatoire |
| lb2 | Répartiteur passif, priorité VRRP 100 | 192.168.63.12 | E1 (`ENABLE_HA=true`) |
| app1 ... app4 | Serveurs applicatifs (API Flask, port 3000 à confirmer) | 192.168.63.21 ... .24 | `NB_APP` de 2 à 4 |
| bdd1 | PostgreSQL primaire | 192.168.63.31 | Obligatoire |
| bdd2 | Réplique PostgreSQL en lecture seule | 192.168.63.32 | Obligatoire |
| obs | Supervision | - | `ENABLE_OBS`, non implémentée |

Ports redirigés vers l'hôte : 8080 vers `lb1`, 8081 vers `lb2` (accès direct). Les deux
ports sont portés par des répartiteurs, ce qui respecte R8.

Remarque : le sujet attribue `192.168.63.0/24` au groupe 8 (X = 55 + G). À faire confirmer
par l'équipe et l'enseignant selon le numéro de groupe réel, car la plage dépend de ce numéro.

## 3. Choix d'architecture et justification

**Répartition.** HAProxy distribue les requêtes en round-robin entre les serveurs
applicatifs : les serveurs sont sans état, donc interchangeables, et cet algorithme suffit à
les charger de façon équitable.

**Sonde de santé (R4).** HAProxy retire du pool tout serveur dont la route `/sante` ne
répond plus HTTP 200. La sonde renvoie 503 si la base ne répond pas : un serveur applicatif
qui a perdu sa base n'est donc plus sollicité. La durée de retrait dépend des paramètres
`inter`, `fall` et `rise` de HAProxy (à confirmer dans `setup-lb.sh` ; le sujet exige moins
de 5 s).

**Redondance du répartiteur (E1).** Keepalived (VRRP) fait basculer la VIP `192.168.63.10`
entre `lb1` (priorité 110) et `lb2` (priorité 100). Si `lb1` tombe, `lb2` reprend la VIP et
le service reste joignable à la même adresse. Le répartiteur passif ne partage pas la charge.

**Configuration par variables (R3, R7).** Le nombre de serveurs (`NB_APP`), l'activation de
`lb2` (`ENABLE_HA`) et les secrets sont dans `.env`. Seul `.env.exemple` est versionné.

**Cloisonnement (R8).** Le trafic interne passe par le réseau privé ; seuls les
répartiteurs exposent un port vers l'hôte.

**Base de données.** `bdd2` est une réplique en flux de `bdd1`. La promotion de `bdd2` est
manuelle (`scripts/failover-db.sh`, confirmation `PROMOUVOIR-BDD2`) et n'est pas répercutée
automatiquement sur les serveurs applicatifs.

## 4. Procédures d'exploitation

### Démarrer

```powershell
Copy-Item .env.exemple .env    # une fois par poste ; ne jamais committer .env
notepad .env                   # remplacer DB_PASSWORD et REPL_PASSWORD
vagrant validate
vagrant up bdd1
vagrant up bdd2
vagrant up app1 app2 app3 app4 # selon NB_APP
vagrant up lb1 lb2             # lb2 seulement si ENABLE_HA=true
```

### Changer le nombre de serveurs applicatifs (R3)

1. Modifier `NB_APP` dans `.env` (de 2 à 4).
2. `vagrant up app3 app4` (les machines ajoutées).
3. `vagrant provision lb1 lb2` pour que HAProxy prenne en compte les serveurs.
4. `./tests/reseau/verif-lb.ps1` : le nombre de serveurs dans `haproxy.cfg` doit être égal
   à `NB_APP`.

### Vérifier le répartiteur

```powershell
./tests/reseau/verif-lb.ps1
Invoke-RestMethod http://192.168.63.10/sante
```

### Tester E1 à la main

```powershell
curl.exe http://192.168.63.10/info    # via la VIP
vagrant halt lb1
curl.exe http://192.168.63.10/info    # doit répondre depuis lb2
vagrant up lb1
```

Le port 8080 passe par `lb1` et ne répond plus quand `lb1` est arrêté : tester la VIP
(ou 8081 pour `lb2`).

## 5. Résultats des scénarios (à compléter avec les mesures réelles)

Pour chaque scénario : commande, résultat brut (fichiers de `tests/reseau/resultats/`) et
commentaire. Ne pas remplir sans avoir exécuté les scripts.

| Scénario | Commande | Mesure attendue | Résultat relevé | Commentaire |
|---|---|---|---|---|
| V1 Répartition | `./tests/reseau/v1-repartition.ps1` | écart plus/moins sollicité < 20 % | à relever | à rédiger |
| V2 Panne d'un serveur | `./tests/reseau/v2-panne-app.ps1` | requêtes perdues, période dégradée < 5 s | à relever | à rédiger |
| V6 Panne du répartiteur | `./tests/reseau/v6-panne-lb.ps1` | temps de reprise < 5 s | à relever | à rédiger |

Les scripts V2 et V6 envoient environ 10 requêtes par seconde de façon séquentielle et
déclenchent la panne à t = 10 s : la résolution est d'environ 0,1 s. La période dégradée est
l'intervalle entre la première et la dernière requête en erreur. Pour V1, faire un relevé
avec `NB_APP=2` et un autre avec `NB_APP=4`. Le dépôt contient aussi `tests/test-api.ps1`,
`tests/test-load.ps1` et `tests/test-failover.ps1` ; la mesure du débit (V3) relève de
l'ingénieur essais.

## 6. Limites connues

- `NB_APP` est limité à 4 ; le sujet demande un nombre paramétrable à partir de 2.
- Les VM partagent le processeur d'un seul poste : ajouter des serveurs ne multiplie pas
  le débit (à discuter avec V3).
- `lb2` est passif : il ne fait que reprendre la VIP.
- La promotion de `bdd2` et la mise à jour de `DB_HOST` sur chaque serveur applicatif sont
  manuelles.
- Le provisionnement se lance machine par machine, dans l'ordre (bases, applications,
  répartiteurs) ; R1 exige qu'un `vagrant destroy -f` suivi d'un `vagrant up` suffise.
- `ENABLE_OBS` n'est pas implémenté.

## 7. Ce que nous ferions autrement

- Rendre le démarrage entièrement automatique (un seul `vagrant up`), avec attente de
  la base avant les serveurs applicatifs.
- Automatiser la mise à jour de `DB_HOST` après la promotion de la réplique.
- Passer le nombre de serveurs à une valeur sans plafond de 4.

## 8. À confirmer dans le code avant la remise

- [ ] Backend HAProxy engendré à partir de `NB_APP`, sans adresse de serveur applicatif en
      dur (−2 points sinon).
- [ ] Sonde : `option httpchk` sur `/sante`, valeurs `inter`, `fall`, `rise`.
- [ ] Un seul `vagrant destroy -f` puis `vagrant up` reconstruit tout (R1).
- [ ] `vagrant provision` rejoué deux fois ne modifie rien (R2).
- [ ] Port de l'API et page de statistiques éventuelle.
- [ ] Mode VRRP (unicast ou multicast) et authentification.
- [ ] Numéro de groupe réel et plage d'adresses correspondante.
