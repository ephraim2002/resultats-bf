# Dossier d'architecture - RÉSULTATS-BF, groupe 2

Livrable L2. Les mesures de la section 6 sont à relever avec les scripts de `tests/` : rien
n'est écrit à l'avance, et une valeur non mesurée ne doit pas figurer dans le dossier remis.

## 1. Contexte

Chaque année, la publication des résultats d'examens fait tomber le site dans les minutes
qui suivent. L'infrastructure doit donc être résiliente (la panne d'une machine ne coupe pas
le service) et scalable (plus de trafic se traite en ajoutant des machines), et entièrement
reconstructible depuis le dépôt, sans geste manuel.

## 2. Architecture

Schéma : `docs/architecture.svg`. Réseau privé `192.168.57.0/24` (groupe 2, X = 55 + 2).

| Machine | Rôle | Adresse |
|---|---|---|
| VIP | IP virtuelle VRRP | 192.168.57.5 |
| lb1 / lb2 | HAProxy + keepalived (actif / passif, E1) | .11 / .12 |
| app1 ... appN | API Flask sans état, port 3000 | .21 ... .2N |
| bdd1 | PostgreSQL primaire | .31 |
| bdd2 | PostgreSQL réplique en flux, Redis (E3) | .32 |

## 3. Choix et justification

**Répartiteur (rôle 1).** HAProxy en round-robin : les serveurs sont sans état, donc
interchangeables. La sonde `GET /sante` (`inter 1s fall 2 rise 2`) retire un serveur en
environ 2 à 3 s en théorie ; `option redispatch` et `retries 2` rejouent une requête sur un
autre serveur quand la connexion échoue. La section `backend` est engendrée par
`scripts/lb.sh` à partir de `config/noeuds.yml`, écrit par le `Vagrantfile` : c'est la source
unique de vérité (R3). keepalived (VRRP, unicast, `advert_int 1`) fait basculer la VIP entre
lb1 (priorité 150) et lb2 (100) ; un script de contrôle (`pidof haproxy`) retire la VIP à un
nœud dont HAProxy est arrêté.

**Application (rôle 2).** Flask derrière gunicorn (2 processus), moins de 100 lignes. Aucun
état local : la connexion à la base est ouverte à la demande, donc l'application démarre même
si la base est absente, et `/sante` renvoie 503 tant qu'elle ne répond pas. Les erreurs de base
renvoient un JSON 503, jamais une page blanche.

**Données (rôle 3).** PostgreSQL 16, répertoire de données local (jamais dans un dossier
synchronisé). `bdd2` est initialisée par `pg_basebackup -R` (réplication en flux). Les secrets
passent par `.env` ; le compte applicatif n'a que le droit `SELECT`. La promotion de `bdd2` est
une procédure scriptée (`scripts/bascule-bdd.sh`) suivie du repointage des applications
(`scripts/app-config.sh`). E3 : Redis sur `bdd2`, protégé par mot de passe, durée de vie
`CACHE_TTL` ; comme les données sont en lecture seule, l'invalidation se fait par expiration,
et une panne de Redis ne casse pas le service.

**Essais (rôle 4).** Scénarios V1 à V6, R5 et E3 en PowerShell (`tests/`), résultats bruts
en CSV ou texte dans `tests/resultats/`.

**Reproductibilité.** Un seul `vagrant up` : les machines sont démarrées dans l'ordre de
définition (bases, applications, répartiteurs). Les scripts écrivent les fichiers en entier
(jamais de `>>`), comparent à l'existant et ne rechargent un service que si le contenu a
changé (R2). Une seule installation de paquets par machine, pour une connexion lente.

## 4. Correspondance avec les exigences

| Exigence | Où | Vérification |
|---|---|---|
| R1 reconstruction | `Vagrantfile`, `scripts/*.sh` | `tests/v5-reconstruction.ps1` |
| R2 idempotence | `scripts/lib.sh` (`maj`, `bloc_fichier`) | `vagrant provision` rejoué deux fois |
| R3 nombre de serveurs | `NB_APP`, `config/noeuds.yml`, `scripts/lb.sh` | `NB_APP=4`, `tests/verif-lb.ps1`, V1 |
| R4 sonde de santé | `scripts/lb.sh`, `/sante` | `tests/v2-panne-app.ps1` |
| R5 réplication | `scripts/replique.sh` | `tests/r5-replication.ps1` |
| R6 bascule | `scripts/bascule-bdd.sh`, `scripts/app-config.sh` | `tests/v4-bascule.ps1` |
| R7 aucun secret | `.env` ignoré, `.env.exemple` versionné | historique Git |
| R8 cloisonnement | un seul `forwarded_port` (lb1) | lecture du `Vagrantfile` |

## 5. Procédures d'exploitation

Démarrer, ajouter des serveurs, basculer la base, reconstruire : voir `README.md`
(sections « Démarrage rapide », « Paramètres », « Bascule de la base »).

## 6. Résultats des scénarios (à compléter avec les mesures réelles)

| Scénario | Commande | Résultat relevé | Commentaire |
|---|---|---|---|
| V1 répartition (N=2 puis N=4) | `./tests/v1-repartition.ps1` | à relever | à rédiger |
| V2 panne d'un serveur | `./tests/v2-panne-app.ps1` | à relever | à rédiger |
| V3 montée en charge | `./tests/v3-charge.ps1` (N=2 puis N=4) | à relever | à rédiger |
| V4 panne de la base, bascule | `./tests/v4-bascule.ps1` | à relever | à rédiger |
| V5 reconstruction | `./tests/v5-reconstruction.ps1` | à relever | à rédiger |
| V6 panne du répartiteur | `./tests/v6-panne-lb.ps1` | à relever | à rédiger |
| R5 réplication | `./tests/r5-replication.ps1` | à relever | à rédiger |
| E3 gain du cache | `./tests/e3-cache.ps1` | à relever | à rédiger |

Les scripts V2 et V6 envoient environ 10 requêtes par seconde de façon séquentielle : la
résolution est d'environ 0,1 s. V3 et E3 lancent `ab` depuis `lb1`, qui partage le processeur
de l'hôte avec les autres VM : les chiffres comparent deux configurations entre elles, ils
ne sont pas un benchmark absolu. Une baisse du débit en passant de 2 à 4 serveurs est un
résultat à expliquer, pas un échec.

## 7. Limites connues

- Les VM partagent le processeur d'un seul poste.
- La bascule de la base est manuelle et ne reconstruit pas bdd1 en réplique.
- Redis est sur `bdd2` : le cache survit à la panne de `bdd1` mais pas à celle de `bdd2`.
- lb2 est passif ; la préemption est active, donc lb1 reprend la VIP à son retour.
- La page de statistiques HAProxy n'a pas d'authentification (réseau privé).
- Les requêtes en cours sur un serveur au moment de sa panne peuvent être perdues.

## 8. Ce que nous ferions autrement

- Automatiser le repointage des applications après promotion et la reconstruction de la
  réplique, avec un outil dédié (Patroni, repmgr).
- Engendrer `haproxy.cfg` avec un moteur de gabarits plutôt qu'avec un script Python en ligne.
- Lire `NB_APP` depuis un fichier versionné plutôt que depuis l'environnement.
- Ajouter l'extension E2 (Prometheus et Grafana) pour observer le débit et les pannes.
