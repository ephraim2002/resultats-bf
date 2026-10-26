\# RESULTATS-BF : partie ingénieur applicatif



Guide pour tester la branche `app/ingenieur-applicatif`.



\## 1. Ce qui a été fait



\- Choix de \*\*Python\*\* pour le service applicatif.

\- `app/app.py` : le service, qui écoute sur le port \*\*3000\*\* et expose `/info`.

\- `app/requirements.txt` : dépendances Python du service.

\- `scripts/setup-app.sh` : première version du script d'installation de la partie applicative.

\- `scripts/app.sh` : script de provisionnement du rôle `app`, appelé par le Vagrantfile (`scripts/<role>.sh`).

\- Branche poussée sur le dépôt du groupe : `app/ingenieur-applicatif`.

\- \*\*Extension E4 (déploiement sans coupure)\*\* : arrêt en douceur du service (`app/app.py`), script de déploiement progressif (`scripts/deploy\_rolling.py`) et test de charge continue (`tests/charge\_continue.py`). Voir la section 7.

\- Pull request ouverte de `app/ingenieur-applicatif` vers `reseau/architecte-reseau`.



\## 2. Ce que fait `scripts/app.sh`



Le script est \*\*rejouable\*\* : on peut le relancer sans effet de bord.



1\. Installe `python3-psycopg2`, `python3-yaml` et `curl`, seulement s'ils manquent.

2\. Lit l'IP de la base dans `config/noeuds.yml` (le nœud de rôle `bdd`). Aucune IP n'est écrite en dur.

3\. Réécrit en entier `/etc/resultats-bf.env` (droits 600) avec `DB\_HOST`, `DB\_PORT`, `DB\_NAME`, `DB\_USER`, `DB\_PASSWORD`, `APP\_PORT=3000`.

4\. Copie `app/app.py` vers `/opt/resultats-bf/app.py`.

5\. Crée le service systemd `resultats-bf` (`Restart=always`), puis le active et le redémarre.

6\. Vérifie que `http://127.0.0.1:3000/info` répond (10 essais, 1 seconde d'écart). Sinon il affiche les logs et sort en erreur.



\## 3. Variables d'environnement



| Variable | Obligatoire | Valeur par défaut |

|---|---|---|

| `DB\_USER` | oui | |

| `DB\_PASSWORD` | oui | |

| `DB\_NAME` | non | `resultats\_bf` (décision du groupe) |

| `DB\_PORT` | non | `5432` |



Si `DB\_USER` ou `DB\_PASSWORD` manque, le script s'arrête avec un message d'erreur clair.



\## 4. Tester la branche



Prérequis : Git, VirtualBox, Vagrant.



Le Vagrantfile se trouve sur la branche `reseau/architecte-reseau`. La branche `app/ingenieur-applicatif` contient uniquement la partie applicative.



```bat

git fetch origin

git checkout app/ingenieur-applicatif

```



Pour tester avec le Vagrantfile, récupérer aussi la branche de l'architecte réseau (ou tester depuis la branche où la PR est fusionnée), puis lancer sous CMD :



```bat

set DB\_USER=monuser

set DB\_PASSWORD=monmotdepasse

vagrant up

```



\## 5. Vérifications attendues



Se connecter à la VM applicative :



```bash

vagrant ssh <nom-de-la-vm-app>

```



Puis :



```bash

curl http://127.0.0.1:3000/info

systemctl status resultats-bf

journalctl -u resultats-bf -n 20

cat /etc/resultats-bf.env

```



| Test | Résultat attendu |

|---|---|

| `curl .../info` | Réponse HTTP 200, \*\*même si la base est absente\*\* |

| `systemctl status resultats-bf` | `active (running)` |

| `/etc/resultats-bf.env` | `DB\_HOST` = IP du nœud `bdd`, `DB\_NAME=resultats\_bf` |

| Relance `vagrant provision <vm-app>` | Aucune erreur, même résultat (rejouable) |

| `sudo systemctl kill resultats-bf` | Le service redémarre tout seul en 1 seconde environ |

| Lancement sans `DB\_USER` | Erreur « DB\_USER manquant » |



\## 6. En cas de problème



\- Le service ne répond pas : `journalctl -u resultats-bf -n 20`.

\- Mauvaise base utilisée : vérifier `DB\_NAME` dans `/etc/resultats-bf.env`.

\- Mauvaise IP de base : vérifier `config/noeuds.yml`.



\## 7. Extension E4 : déploiement sans coupure



\### Objectif

Mettre à jour le service sur les serveurs applicatifs \*\*sans interruption pour les utilisateurs\*\* : pendant le déploiement, aucune requête ne doit échouer.



\### Fichiers

| Fichier | Rôle |

|---|---|

| `app/app.py` | Arrêt en douceur : à la réception de `SIGTERM`, le service cesse d'accepter de nouvelles connexions, termine les requêtes en cours, puis s'arrête proprement |

| `scripts/deploy\_rolling.py` | Déploiement progressif (rolling) : met à jour les serveurs applicatifs un par un |

| `tests/charge\_continue.py` | Envoie des requêtes en continu pendant le déploiement et compte les erreurs |



\### Principe du déploiement progressif

Pour chaque serveur applicatif, l'un après l'autre :



1\. Retirer le serveur du répartiteur de charge (le trafic va vers les autres).

2\. Envoyer `SIGTERM` au service : il termine ses requêtes en cours puis s'arrête.

3\. Copier la nouvelle version de `app.py` et redémarrer le service `resultats-bf`.

4\. Attendre que `/info` réponde de nouveau (même contrôle que dans `app.sh`).

5\. Remettre le serveur dans le répartiteur de charge, puis passer au suivant.



Il y a donc toujours au moins un serveur applicatif disponible.



\### Tester E4

Prérequis : au moins \*\*deux\*\* serveurs applicatifs et le répartiteur de charge démarrés (`vagrant up`).



Terminal 1 : lancer la charge continue (via l'adresse du répartiteur de charge) :



```bat

python tests\\charge\_continue.py

```



Terminal 2 : pendant que la charge tourne, lancer le déploiement :



```bat

python scripts\\deploy\_rolling.py

```



Les arguments exacts (adresse du répartiteur de charge, liste des serveurs, durée) sont à compléter selon les scripts : `<A COMPLETER>`.



\### Résultats attendus

| Test | Résultat attendu |

|---|---|

| Charge continue pendant le déploiement | \*\*0 requête en erreur\*\* |

| `sudo systemctl stop resultats-bf` pendant une requête longue | La requête en cours se termine avant l'arrêt |

| Après le déploiement | Tous les serveurs applicatifs sont sur la nouvelle version, `/info` répond partout |

| Comparaison | Même test avec un arrêt brutal (sans arrêt en douceur) : des erreurs apparaissent, ce qui prouve l'intérêt de E4 |



\## 8. Règle du groupe



Les branches ne sont fusionnées dans `main` qu'à la fin du travail.

