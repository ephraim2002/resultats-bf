# RÉSULTATS-BF

Projet de travaux pratiques de virtualisation et cloud : déploiement d'une
infrastructure résiliente et extensible pour consulter des résultats scolaires.
Vagrant orchestre les machines virtuelles, PostgreSQL stocke et réplique les
résultats, les serveurs applicatifs exposent une API Flask et HAProxy répartit
les requêtes HTTP.

## Architecture

Avec les valeurs de [`.env.exemple`](./.env.exemple) (`NB_APP=4` et
`ENABLE_HA=true`), l'infrastructure comprend huit machines :

| Machine | Adresse privée | Rôle |
| --- | --- | --- |
| `lb1` | `192.168.63.11` | HAProxy/Keepalived, priorité VRRP 110 |
| `lb2` | `192.168.63.12` | HAProxy/Keepalived, priorité VRRP 100 (si `ENABLE_HA=true`) |
| `app1` | `192.168.63.21` | Serveur applicatif |
| `app2` | `192.168.63.22` | Serveur applicatif |
| `app3` | `192.168.63.23` | Serveur applicatif, si `NB_APP` vaut au moins 3 |
| `app4` | `192.168.63.24` | Serveur applicatif, si `NB_APP=4` |
| `bdd1` | `192.168.63.31` | Base PostgreSQL primaire |
| `bdd2` | `192.168.63.32` | Réplique PostgreSQL en lecture seule |

Keepalived fait basculer l'adresse IP virtuelle `192.168.63.10` entre les
répartiteurs. HAProxy distribue les requêtes à tour de rôle (round-robin) et
retire du pool les applications dont la route `/sante` ne répond plus HTTP 200.
Le port `8080` de l'hôte est redirigé vers `lb1` ; `8081` permet d'accéder
directement à `lb2`. Pour tester la VIP et le basculement, utiliser
`http://192.168.63.10`.

Les adresses, ressources mémoire et provisionneurs sont configurés dans le
[`Vagrantfile`](./Vagrantfile). Le réseau privé utilisé est `192.168.63.0/24`.
La base `resultats` est créée à partir de
[`database/schema.sql`](./database/schema.sql) et alimentée par
[`database/seed.sql`](./database/seed.sql) (50 000 résultats).
La réplication PostgreSQL est configurée de `bdd1` vers `bdd2`. La promotion
de la réplique en cas de panne de la base primaire est une opération manuelle ;
elle ne bascule pas automatiquement les applications.

## Prérequis

- Windows avec PowerShell.
- [VirtualBox](https://www.virtualbox.org/) installé et fonctionnel.
- [Vagrant](https://developer.hashicorp.com/vagrant/install) installé et
  disponible dans le `PATH`.
- Une connexion Internet lors du premier démarrage, pour télécharger la box
  Ubuntu et installer les paquets des VM.
- Environ 4,5 Go de mémoire vive pour les VM avec quatre applications et deux
  répartiteurs ; prévoir environ 1 Go de plus si `ENABLE_OBS=true`, sans
  compter les ressources nécessaires à Windows.

Vérifier les installations :

```powershell
vagrant --version
VBoxManage --version
```

## Préparer la configuration

Depuis le dossier du projet, copier le modèle d'environnement puis modifier les
secrets :

```powershell
Copy-Item .env.exemple .env
notepad .env
```

Remplacer au minimum les valeurs d'exemple de `DB_PASSWORD` et
`REPL_PASSWORD` par des mots de passe robustes et différents. Le fichier `.env`
est ignoré par Git : ne pas le versionner ni partager son contenu.

Les paramètres utiles du modèle sont :

| Variable | Valeur par défaut | Description |
| --- | --- | --- |
| `NB_APP` | `4` dans le modèle | Nombre de VM applicatives, de 2 à 4 |
| `DB_NAME` | `resultats` | Nom de la base de données |
| `DB_USER` | `resultats_app` | Compte PostgreSQL de l'application |
| `DB_PASSWORD` | à définir | Mot de passe du compte applicatif |
| `REPL_USER` | `repli_user` | Compte PostgreSQL de réplication |
| `REPL_PASSWORD` | à définir | Mot de passe du compte de réplication |
| `ENABLE_HA` | `true` dans le modèle | Ajoute et provisionne le répartiteur `lb2` |
| `ENABLE_OBS` | `false` | Ajoute et provisionne Prometheus et Grafana sur `obs` |

`NB_APP` doit rester compris entre 2 et 4. Pour activer la haute disponibilité
des répartiteurs, conserver `ENABLE_HA=true` dans `.env`. Pour activer
l'observabilité, définir `ENABLE_OBS=true` dans `.env`. Cette option ajoute la
VM `obs`, qui héberge Prometheus et Grafana.

## Valider et démarrer l'infrastructure

Valider la syntaxe et la configuration avant de lancer les VM :

```powershell
vagrant validate
```

Pour provisionner dans l'ordre (la réplique dépend de la base primaire), lancer
les commandes suivantes depuis le dossier du projet :

```powershell
vagrant up bdd1
vagrant up bdd2
vagrant up app1 app2 app3 app4
vagrant up lb1 lb2
```

Ces commandes correspondent à la configuration du modèle (`NB_APP=4` et
`ENABLE_HA=true`). Si `ENABLE_OBS=true` est aussi défini, démarrer et
provisionner la VM d'observabilité :

```powershell
vagrant up obs
```

`vagrant up` démarre chaque VM demandée et exécute son provisionneur. Si tu as
choisi moins de quatre applications ou désactivé la haute disponibilité,
retire les noms de VM correspondants des commandes. Par exemple, avec
`NB_APP=2` et `ENABLE_HA=false`, utilise `vagrant up app1 app2` et
`vagrant up lb1`.

Pour créer toutes les VM sans lancer les provisionneurs, puis les provisionner
explicitement :

```powershell
vagrant up --no-provision
vagrant provision bdd1
vagrant provision bdd2
vagrant provision app1
vagrant provision app2
vagrant provision app3
vagrant provision app4
vagrant provision lb1
vagrant provision lb2
vagrant provision obs
```

La deuxième méthode doit également respecter l'ordre `bdd1`, `bdd2`, les
applications, puis les répartiteurs et enfin `obs`. Ne provisionner `app3`,
`app4`, `lb2` et `obs` que si ces VM sont activées dans `.env`.

## Observabilité

Avec `ENABLE_OBS=true`, la VM `obs` (`192.168.63.41`) installe et démarre
Prometheus et Grafana. Le script `setup-observability.sh` configure Prometheus
pour collecter les métriques toutes les 15 secondes et ajoute automatiquement
Prometheus comme source de données par défaut dans Grafana. Le script
`setup-node-exporter.sh` installe Node Exporter sur chaque VM ; il expose les
métriques système sur le port `9100` du réseau privé. Si les autres VM étaient
déjà créées avant l'ajout du provisionneur Node Exporter, les reprovisionner
avec `vagrant provision` pour installer l'exporter sur celles-ci.

| Outil | Accès depuis Windows | Fonction |
| --- | --- | --- |
| Grafana | [http://localhost:3000](http://localhost:3000) | Tableaux de bord et visualisation des métriques |
| Prometheus | [http://localhost:9090](http://localhost:9090) | Collecte, exploration et requêtes PromQL |
| Node Exporter | `http://<IP-de-la-VM>:9100/metrics` sur le réseau privé | Exposition des métriques système d'une VM |

Les ports Grafana `3000` et Prometheus `9090` sont redirigés vers l'hôte sur
`127.0.0.1`. Lors de la première connexion à Grafana, les identifiants
initiaux du paquet sont `admin` / `admin` ; Grafana demande de définir un
nouveau mot de passe. Ne conserve pas le mot de passe initial.

Pour démarrer l'observabilité après avoir activé `ENABLE_OBS=true` dans `.env` :

```powershell
vagrant up obs
```

Pour vérifier l'état des services et la configuration Prometheus :

```powershell
vagrant ssh obs -c "sudo systemctl is-active prometheus"
vagrant ssh obs -c "sudo systemctl is-active grafana-server"
vagrant ssh obs -c "sudo promtool check config /etc/prometheus/prometheus.yml"
Invoke-RestMethod http://localhost:9090/-/ready
Invoke-RestMethod http://localhost:3000/api/health
```

Dans l'interface Prometheus, ouvre `Status` puis `Targets` pour vérifier les
cibles de collecte. Les cibles Node Exporter sont déclarées dans
`/etc/prometheus/prometheus.yml` : `bdd1`, `bdd2`, `app1` à `app4`, `lb1`,
`lb2` et `obs`. Les machines optionnelles qui ne sont pas démarrées ou activées
apparaîtront comme indisponibles (`DOWN`) ; cela ne signifie pas nécessairement
que Prometheus est en panne. Les cibles activées doivent passer à `UP` après
leur provisionnement.

Exemples de requêtes PromQL à essayer dans Prometheus ou dans l'explorateur de
Grafana :

```promql
# Nombre de cibles de collecte actives
up

# Pourcentage d'utilisation CPU par machine
100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))

# Utilisation de la mémoire en octets par machine
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes
```

La source de données Prometheus est provisionnée automatiquement, mais aucun
tableau de bord Grafana n'est installé par le script à ce stade. Tu peux créer
un tableau de bord dans Grafana et y ajouter les requêtes PromQL ci-dessus.
Node Exporter fournit des métriques système ; cette configuration ne collecte
pas les métriques propres à PostgreSQL, HAProxy ou à l'API.

## Provisionnement et administration

Afficher l'état des machines :

```powershell
vagrant status
```

Relancer le provisionnement de toute l'infrastructure ou d'une machine précise
après une modification :

```powershell
vagrant provision
vagrant provision bdd1
vagrant provision bdd2
vagrant provision app1
vagrant provision app2
vagrant provision lb1
vagrant provision lb2
```

Ouvrir une session SSH dans une VM :

```powershell
vagrant ssh bdd1
```

Arrêter, redémarrer ou supprimer les VM :

```powershell
vagrant halt
vagrant reload
vagrant destroy
```

`vagrant destroy` supprime les VM et leurs données locales. Il faut confirmer
l'opération dans Vagrant ; ne l'utiliser que si cette suppression est voulue.

## Vérifications de l'infrastructure

### Base primaire

Vérifier que PostgreSQL répond et compter les résultats importés :

```powershell
vagrant ssh bdd1 -c "sudo systemctl is-active postgresql"
vagrant ssh bdd1 -c "sudo -u postgres psql -d resultats -c 'SELECT COUNT(*) FROM resultats;'"
```

Le jeu de données initial contient 50 000 lignes.

### Réplication

Vérifier que PostgreSQL tourne sur la réplique et qu'elle est bien en mode
standby (`t` signifie vrai) :

```powershell
vagrant ssh bdd2 -c "sudo systemctl is-active postgresql"
vagrant ssh bdd2 -c "sudo -u postgres psql -tAc 'SELECT pg_is_in_recovery();'"
```

### HAProxy

Vérifier la syntaxe de HAProxy et l'état des services sur les deux répartiteurs :

```powershell
vagrant ssh lb1 -c "sudo haproxy -c -f /etc/haproxy/haproxy.cfg"
vagrant ssh lb1 -c "sudo systemctl is-active haproxy"
vagrant ssh lb1 -c "sudo systemctl is-active keepalived"
vagrant ssh lb2 -c "sudo systemctl is-active haproxy"
vagrant ssh lb2 -c "sudo systemctl is-active keepalived"
```

Depuis Windows, vérifier l'API via la VIP et vérifier la présence de l'adresse
virtuelle sur le répartiteur actif :

```powershell
Invoke-RestMethod http://192.168.63.10/sante
vagrant ssh lb1 -c "ip -4 addr show"
vagrant ssh lb2 -c "ip -4 addr show"
```

L'adresse `192.168.63.10` doit apparaître sur le répartiteur actif. Le port
redirigé local `127.0.0.1:8080` pointe directement sur `lb1` et ne remplace pas
le test de la VIP en cas d'arrêt de ce répartiteur.

## Tests de l'API, de la scalabilité et de la résilience

Les tests PowerShell s'exécutent depuis le dossier racine du projet, avec les
VM configurées et provisionnées.

Tester la santé et la recherche d'un résultat via HAProxy :

```powershell
.\tests\test-api.ps1
```

Vérifier la répartition des requêtes entre plusieurs serveurs applicatifs :

```powershell
.\tests\test-load.ps1
```

Ce test effectue 20 requêtes à `/info`, affiche le nom des serveurs ayant
répondu et signale si au moins deux applications ont été observées. Il s'agit
d'un test de répartition, pas d'un benchmark de débit.

Tester la résilience des répartiteurs nécessite `ENABLE_HA=true` et les deux
VM `lb1` et `lb2` en marche. Le test arrête temporairement `lb1`, vérifie que
la VIP continue de répondre via `lb2`, puis tente de redémarrer `lb1` :

```powershell
.\tests\test-failover.ps1
```

Le test de bascule PostgreSQL est manuel. Après vérification que `bdd2` est à
jour, lancer la promotion depuis cette VM ; le script demande la confirmation
explicite `PROMOUVOIR-BDD2` :

```bash
vagrant ssh bdd2
sudo bash /vagrant/scripts/failover-db.sh
```

Après la promotion, mettre à jour `DB_HOST` dans `/etc/resultats-bf.env` sur
chaque VM applicative et redémarrer `resultats-api`. Cette étape n'est pas
automatisée par le script de promotion.

Pour contrôler la réplication des données, insérer un résultat dans la base
primaire puis vérifier sa présence sur `bdd2` :

Depuis PowerShell, ouvrir la session sur la base primaire :

```powershell
vagrant ssh bdd1
```

Dans la VM `bdd1`, ouvrir `psql` et effectuer l'insertion :

```bash
sudo -u postgres psql -d resultats
```

Dans `psql` :

```sql
INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
VALUES ('TESTREPLI001', 'Test Replication', 'H', 12.50, true)
ON CONFLICT (matricule) DO NOTHING;

SELECT * FROM resultats WHERE matricule = 'TESTREPLI001';
```

Quitter `psql` avec `\q`, puis la VM avec `exit`. Depuis PowerShell, ouvrir
une session sur la réplique :

```powershell
vagrant ssh bdd2
```

Dans la VM `bdd2`, vérifier la ligne répliquée :

```bash
sudo -u postgres psql -d resultats
```

Dans cette session `psql`, exécuter :

```sql
SELECT * FROM resultats WHERE matricule = 'TESTREPLI001';
```

## Arrêt et nettoyage

Arrêter les machines en conservant leur état :

```powershell
vagrant halt
```

Supprimer les machines virtuelles :

```powershell
vagrant destroy
```

## Fichiers principaux

- [`Vagrantfile`](./Vagrantfile) : définition des VM, des réseaux et des ports.
- [`scripts/setup-database.sh`](./scripts/setup-database.sh) : installation et
  configuration de PostgreSQL primaire.
- [`scripts/setup-replica.sh`](./scripts/setup-replica.sh) : initialisation de
  la réplique PostgreSQL.
- [`scripts/setup-lb.sh`](./scripts/setup-lb.sh) : configuration de HAProxy.
- [`scripts/setup-lb-ha.sh`](./scripts/setup-lb-ha.sh) : configuration de
  HAProxy et Keepalived sur les deux répartiteurs.
- [`scripts/setup-observability.sh`](./scripts/setup-observability.sh) :
  installation et configuration de Prometheus et Grafana sur `obs`.
- [`scripts/setup-node-exporter.sh`](./scripts/setup-node-exporter.sh) :
  installation de Node Exporter sur les machines provisionnées.
- [`scripts/failover-db.sh`](./scripts/failover-db.sh) : promotion manuelle de
  la réplique PostgreSQL après confirmation.
- [`tests/test-api.ps1`](./tests/test-api.ps1),
  [`tests/test-load.ps1`](./tests/test-load.ps1) et
  [`tests/test-failover.ps1`](./tests/test-failover.ps1) : tests de l'API, de
  la répartition des requêtes et du basculement de la VIP.
- [`database/schema.sql`](./database/schema.sql) et
  [`database/seed.sql`](./database/seed.sql) : schéma et données initiales.
