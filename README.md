# RÉSULTATS-BF - groupe 18

Plateforme de consultation de résultats d'examens, résiliente et extensible, entièrement
décrite en code avec Vagrant et VirtualBox (projet de groupe M1, module DevOps et
infrastructures reproductibles). Un candidat consulte son résultat à partir de son
matricule ; la panne d'une machine ne doit pas interrompre le service, et absorber plus de
trafic se fait en ajoutant des serveurs applicatifs.

## Architecture

Réseau privé du groupe 18 (numéro de groupe du TP : 8) : `192.168.63.0/24`. Schéma : `docs/architecture.svg`.

| Machine | Rôle | Adresse | RAM |
|---|---|---|---|
| (VIP) | IP virtuelle partagée par lb1 et lb2 (VRRP) | 192.168.63.10 | - |
| lb1 | HAProxy + keepalived, actif | 192.168.63.11 | 512 Mo |
| lb2 | HAProxy + keepalived, passif (extension E1) | 192.168.63.12 | 512 Mo |
| app1 ... appN | API Flask + gunicorn, sans état (`NB_APP`, de 2 à 9) | 192.168.63.21 ... .2N | 512 Mo |
| bdd1 | PostgreSQL primaire | 192.168.63.31 | 768 Mo |
| bdd2 | PostgreSQL réplique en flux + Redis (extension E3) | 192.168.63.32 | 768 Mo |

HAProxy répartit les requêtes en round-robin et n'envoie du trafic qu'aux serveurs dont
`GET /sante` renvoie 200. Sa configuration est engendrée à partir de `config/noeuds.yml`,
lui-même écrit par le `Vagrantfile` : aucune adresse de serveur n'est écrite en dur.
Seul `lb1` expose un port vers l'hôte (8080).

L'API expose trois points d'entrée :

| Requête | Réponse |
|---|---|
| `GET /resultat?matricule=BF000042` | Résultat du candidat en JSON (404 si inconnu, 503 si la base est indisponible) |
| `GET /sante` | 200 si la base répond, 503 sinon (sonde de HAProxy) |
| `GET /info` | Nom d'hôte du serveur qui a répondu |

## Prérequis

- Windows avec PowerShell, ou Linux/macOS.
- VirtualBox 6.1.28 ou plus récent, Vagrant, Git.
- Connexion Internet au premier démarrage (boîte Ubuntu et paquets).
- Environ 4 Go de RAM libre pour les VM avec les valeurs par défaut (2 serveurs applicatifs,
  deux répartiteurs) ; environ 3 Go avec `LB2=0`.

```powershell
git --version
vagrant --version
VBoxManage --version
```

## Démarrage rapide

```powershell
git clone <url-du-depot> resultats-bf
cd resultats-bf
Copy-Item .env.exemple .env      # puis remplacer les mots de passe dans .env
vagrant up                       # un seul up : tout est provisionné dans l'ordre
```

Vérifier le résultat :

```powershell
curl.exe http://192.168.63.10/info
curl.exe "http://192.168.63.10/resultat?matricule=BF000042"
curl.exe http://localhost:8080/sante
```

Le fichier `.env` n'est jamais versionné. Le modèle `.env.exemple` contient les noms des
variables : `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `REPL_USER`, `REPL_PASSWORD`,
`REDIS_PASSWORD`. N'utiliser ni espaces, ni guillemets, ni `#` dans les valeurs.

## Paramètres

| Variable | Défaut | Effet |
|---|---|---|
| `NB_APP` | 2 | Nombre de serveurs applicatifs (2 à 9) |
| `LB2` | actif | `LB2=0` supprime lb2 et keepalived (économie de RAM) |
| `GROUPE` | 8 | Numéro de groupe, donc plage `192.168.(55+G).0/24` |

Sous PowerShell, une variable se définit pour la session :

```powershell
$env:NB_APP = 4
vagrant up                         # crée app3 et app4
vagrant provision lb1 lb2          # HAProxy prend en compte les nouveaux serveurs
Remove-Item Env:NB_APP             # revient à la valeur par défaut
```

`NB_APP` doit être défini à chaque commande `vagrant` qui régénère `config/noeuds.yml` ;
sinon la configuration revient à 2 serveurs.

## Exploitation

```powershell
vagrant status
vagrant provision            # rejouable : ne modifie rien si rien n'a changé (R2)
vagrant halt                 # arrête les VM
vagrant destroy -f ; vagrant up    # reconstruction complète (R1)
```

Statistiques HAProxy (réseau privé) : `vagrant ssh lb1 -c "curl -s 192.168.63.11:8404"`.

### Bascule de la base (R6)

Si bdd1 tombe, `/sante` renvoie 503 et HAProxy retire les serveurs applicatifs du pool. La
procédure promeut bdd2 puis repointe les serveurs applicatifs ; elle est chronométrée par
`tests/v4-bascule.ps1` et se fait à la main ainsi :

```powershell
vagrant ssh bdd2 -c "sudo bash /vagrant/scripts/bascule-bdd.sh"
vagrant ssh app1 -c "sudo bash /vagrant/scripts/app-config.sh DB_HOST 192.168.63.32"
vagrant ssh app2 -c "sudo bash /vagrant/scripts/app-config.sh DB_HOST 192.168.63.32"
```

(une commande par serveur applicatif). Après une bascule, bdd1 est obsolète : reconstruire
l'infrastructure avec `vagrant destroy -f` puis `vagrant up`.

## Scénarios de validation

Les scripts s'exécutent depuis la racine du dépôt, une fois `vagrant up` terminé.
Les résultats bruts sont écrits dans `tests/resultats/`.

| Scénario | Commande |
|---|---|
| Contrôle du répartiteur (R3, R4, R8, E1) | `./tests/verif-lb.ps1` |
| R5 - réplication | `./tests/r5-replication.ps1` |
| V1 - répartition | `./tests/v1-repartition.ps1` |
| V2 - panne d'un serveur applicatif | `./tests/v2-panne-app.ps1` |
| V3 - montée en charge (N=2 puis N=4) | `./tests/v3-charge.ps1` |
| V4 - panne de la base et bascule | `./tests/v4-bascule.ps1` |
| V5 - reconstruction | `./tests/v5-reconstruction.ps1` |
| V6 - panne du répartiteur (E1) | `./tests/v6-panne-lb.ps1` |
| E3 - gain du cache Redis | `./tests/e3-cache.ps1` |

Si PowerShell refuse d'exécuter les scripts : `Set-ExecutionPolicy -Scope Process Bypass`.

## Extensions réalisées

- **E1 - répartiteur redondant** : lb2, keepalived (VRRP, unicast), IP virtuelle `192.168.63.10`.
  Test : `vagrant halt lb1` et le service reste joignable via la VIP.
- **E3 - cache** : Redis sur bdd2, utilisé par l'API pour les consultations répétées
  (durée de vie `CACHE_TTL`, 60 s par défaut). Les données étant en lecture seule, l'invalidation
  se fait par expiration. Une panne de Redis n'interrompt pas le service : l'API lit la base.

## Structure du dépôt

```
Vagrantfile            machines, réseau, paramètres ; écrit config/noeuds.yml
.env.exemple           modèle des variables (le vrai .env n'est pas versionné)
app/app.py             API Flask (moins de 100 lignes)
database/              schéma et jeu de 50 000 résultats
scripts/               provisionnement (bdd, replique, app, lb) et outils d'exploitation
tests/                 scénarios PowerShell et résultats bruts
docs/                  schéma, dossier d'architecture, journal de bord
```

## Dépannage

- **Service injoignable** : un service qui écoute sur `127.0.0.1` n'est joignable de personne ;
  tous les services de ce dépôt écoutent sur `0.0.0.0` (ou l'adresse privée).
- **`Fichier .env manquant`** : créer le `.env` à côté du `Vagrantfile` (`Copy-Item .env.exemple .env`).
  Le `Vagrantfile` le vérifie à chaque commande `vagrant`, y compris `vagrant box add`.
- **Scripts qui échouent avec des erreurs étranges** : fins de ligne CRLF ; le fichier
  `.gitattributes` force LF, cloner après sa mise en place.
- **HAProxy renvoie 503** : aucun serveur applicatif ne répond à `/sante` ; vérifier la base
  (`vagrant ssh app1 -c "sudo journalctl -u resultats-api -n 30"`).

## Limites connues

- Les VM partagent le processeur d'un seul poste : doubler les serveurs ne double pas le débit.
- La bascule de la base est manuelle et ne reconstruit pas bdd1 en réplique.
- lb2 est passif : il reprend la VIP, il ne partage pas la charge.
- La page de statistiques HAProxy n'est pas protégée (réseau privé uniquement).
