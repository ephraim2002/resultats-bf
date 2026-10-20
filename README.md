# RÉSULTATS-BF

Projet de travaux pratiques de virtualisation et cloud : déploiement d'une
infrastructure pour consulter des résultats scolaires. Vagrant orchestre les
machines virtuelles, PostgreSQL stocke les résultats, et HAProxy répartit les
requêtes HTTP vers les serveurs applicatifs.

> **État actuel du dépôt :** l'infrastructure et le provisionnement de la base
> primaire, de sa réplique et de HAProxy sont décrits dans le
> [`Vagrantfile`](./Vagrantfile) et les scripts correspondants. En revanche,
> [`app/app.py`](./app/app.py), [`scripts/setup-app.sh`](./scripts/setup-app.sh)
> et les scripts de [`tests/`](./tests/) sont actuellement vides. Les
> vérifications de l'API et de la répartition ci-dessous sont donc des tests à
> effectuer une fois l'application implémentée ; elles ne réussiront pas avec
> l'état actuel du dépôt.

## Architecture

La configuration Vagrant crée par défaut six machines :

| Machine | Adresse privée | Rôle |
| --- | --- | --- |
| `lb1` | `192.168.63.11` | HAProxy, port HTTP `80` redirigé vers le port `8080` de l'hôte |
| `app1` | `192.168.63.21` | Serveur applicatif |
| `app2` | `192.168.63.22` | Serveur applicatif |
| `bdd1` | `192.168.63.31` | Base PostgreSQL primaire |
| `bdd2` | `192.168.63.32` | Réplique PostgreSQL en lecture seule |

Les adresses, ressources mémoire et scripts sont configurés dans le
[`Vagrantfile`](./Vagrantfile). Le réseau privé utilisé est `192.168.63.0/24`.
La base `resultats` est créée à partir de
[`database/schema.sql`](./database/schema.sql) et alimentée par
[`database/seed.sql`](./database/seed.sql) (50 000 résultats).

## Prérequis

- Windows avec PowerShell.
- [VirtualBox](https://www.virtualbox.org/) installé et fonctionnel.
- [Vagrant](https://developer.hashicorp.com/vagrant/install) installé et
  disponible dans le `PATH`.
- Une connexion Internet lors du premier démarrage, pour télécharger la box
  Ubuntu et installer les paquets des VM.
- Environ 3 Go de mémoire vive disponibles pour les VM par défaut, en plus des
  ressources nécessaires à Windows. Prévoir davantage pour l'hôte.

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
| `NB_APP` | `2` | Nombre de VM applicatives, de 2 à 4 |
| `DB_NAME` | `resultats` | Nom de la base de données |
| `DB_USER` | `resultats_app` | Compte PostgreSQL de l'application |
| `DB_PASSWORD` | à définir | Mot de passe du compte applicatif |
| `REPL_USER` | `repli_user` | Compte PostgreSQL de réplication |
| `REPL_PASSWORD` | à définir | Mot de passe du compte de réplication |
| `ENABLE_HA` | `false` | Ajoute la VM `lb2` |
| `ENABLE_OBS` | `false` | Ajoute la VM `obs` |

`NB_APP` doit rester compris entre 2 et 4. Les options `ENABLE_HA` et
`ENABLE_OBS` ajoutent actuellement les VM dans Vagrant ; leur provisionnement
complet n'est pas encore disponible.

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
vagrant up app1 app2
vagrant up lb1
```

`vagrant up` démarre la VM demandée et exécute son provisionneur. Les noms
disponibles dépendent de `NB_APP` ; par exemple, avec `NB_APP=3`, les VM
applicatives sont `app1`, `app2` et `app3`.

Pour créer toutes les VM sans lancer les provisionneurs, puis les provisionner
explicitement :

```powershell
vagrant up --no-provision
vagrant provision bdd1
vagrant provision bdd2
vagrant provision app1
vagrant provision app2
vagrant provision lb1
```

La deuxième méthode doit également respecter l'ordre `bdd1`, `bdd2`, les
applications, puis `lb1`.

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
vagrant provision lb1
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

Vérifier la syntaxe de la configuration et l'état du service :

```powershell
vagrant ssh lb1 -c "sudo haproxy -c -f /etc/haproxy/haproxy.cfg"
vagrant ssh lb1 -c "sudo systemctl is-active haproxy"
```

Depuis Windows, vérifier que le port HTTP transféré est joignable :

```powershell
curl.exe -i http://127.0.0.1:8080/sante
```

HAProxy utilise `GET /sante` comme contrôle de santé pour les serveurs
applicatifs. Tant que l'application et son provisionneur sont vides, il est
normal que cette requête échoue ou que HAProxy ne dispose d'aucun serveur sain.

## Tests de l'application (après implémentation)

Les commandes ci-dessous reprennent les vérifications prévues dans le projet.
Elles supposent que le provisionnement de l'application installe et démarre le
service `resultats-api` sur le port `5000` et expose les routes indiquées.

Vérifier le service et la route de santé sur chaque VM applicative :

```powershell
vagrant ssh app1 -c "sudo systemctl status resultats-api --no-pager"
vagrant ssh app1 -c "curl -i http://127.0.0.1:5000/sante"
vagrant ssh app2 -c "sudo systemctl is-active resultats-api"
vagrant ssh app2 -c "curl -fsS http://127.0.0.1:5000/sante"
```

Tester la consultation d'un résultat :

```powershell
vagrant ssh app1 -c "curl -i 'http://127.0.0.1:5000/resultat?matricule=MAT000001'"
```

Tester les routes à travers HAProxy depuis Windows :

```powershell
curl.exe -i http://127.0.0.1:8080/sante
curl.exe -i "http://127.0.0.1:8080/resultat?matricule=MAT000001"
```

Si la route `/info` est implémentée pour indiquer le serveur qui a répondu,
répéter les requêtes afin d'observer la répartition :

```powershell
1..10 | ForEach-Object {
    $r = Invoke-RestMethod "http://127.0.0.1:8080/info"
    $r | ConvertTo-Json -Compress
}
```

Les fichiers [`tests/test-api.ps1`](./tests/test-api.ps1),
[`tests/test-load.ps1`](./tests/test-load.ps1) et
[`tests/test-failover.ps1`](./tests/test-failover.ps1) sont prévus pour les
tests automatisés, mais sont vides actuellement. Il n'y a donc pas encore de
commande de test automatisé fonctionnelle à exécuter.

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
- [`database/schema.sql`](./database/schema.sql) et
  [`database/seed.sql`](./database/seed.sql) : schéma et données initiales.
