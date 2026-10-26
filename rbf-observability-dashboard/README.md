# RÉSULTATS-BF — dashboard Grafana + débit HAProxy

Ce paquet fournit :
- un dashboard Grafana JSON provisionnable automatiquement ;
- le provider Grafana ;
- le fragment de scrape Prometheus pour `lb1` et `lb2` ;
- le frontend HAProxy qui expose les métriques natives sur `:8404`.

## 1. Copier le dashboard et son provider

Depuis la racine du dépôt, créer les répertoires si nécessaire et copier :
- `grafana/dashboards/resultats-bf.json` vers `/var/lib/grafana/dashboards/resultats-bf.json` dans la VM `obs` ;
- `grafana/provisioning/dashboards/resultats-bf.yml` vers `/etc/grafana/provisioning/dashboards/resultats-bf.yml` dans `obs`.

Le script `scripts/setup-observability.sh` copie automatiquement ces fichiers depuis le partage `/vagrant` pendant le provisionnement de `obs`.
```bash
install -d -o grafana -g grafana -m 755 /var/lib/grafana/dashboards
install -d -m 755 /etc/grafana/provisioning/dashboards
install -m 644 /vagrant/rbf-observability-dashboard/grafana/dashboards/resultats-bf.json /var/lib/grafana/dashboards/resultats-bf.json
install -m 644 /vagrant/rbf-observability-dashboard/grafana/provisioning/dashboards/resultats-bf.yml /etc/grafana/provisioning/dashboards/resultats-bf.yml
chown -R grafana:grafana /var/lib/grafana/dashboards
```
Vagrant monte le projet dans `/vagrant`; le script de provisionnement dépend de ce partage.

## 2. Activer les métriques HAProxy sur lb1 et lb2

Le script `scripts/setup-lb.sh` ajoute automatiquement `haproxy/prometheus-metrics.cfg` à la configuration HAProxy générée. Il ne faut pas remplacer les sections `global`, `defaults`, `frontend` ou `backend` déjà générées.

Valider puis recharger HAProxy sur les deux machines :
```powershell
vagrant ssh lb1 -c "sudo haproxy -c -f /etc/haproxy/haproxy.cfg"
vagrant ssh lb2 -c "sudo haproxy -c -f /etc/haproxy/haproxy.cfg"
```
Reprovisionner uniquement les load balancers pour appliquer la configuration :
```powershell
vagrant provision lb1
vagrant provision lb2
```
Ensuite vérifier les métriques :
```powershell
vagrant ssh lb1 -c "curl -fsS http://127.0.0.1:8404/metrics | head"
vagrant ssh lb2 -c "curl -fsS http://127.0.0.1:8404/metrics | head"
```
Si HAProxy signale que `prometheus-exporter` est un service inconnu, la version du paquet n'a pas été compilée avec le support Prometheus ; ne pas continuer avec ces requêtes et signaler l'erreur pour adapter l'exporter.

## 3. Ajouter le job HAProxy dans Prometheus

Le script `scripts/setup-observability.sh` ajoute automatiquement le job de `prometheus/haproxy-scrape.yml` sous la clé existante `scrape_configs:`. Reprovisionner `obs` pour appliquer la configuration.

Valider et redémarrer :
```powershell
vagrant ssh obs -c "sudo promtool check config /etc/prometheus/prometheus.yml"
vagrant ssh obs -c "sudo systemctl restart prometheus"
vagrant ssh obs -c "curl -fsS http://127.0.0.1:9090/api/v1/targets"
```

## 4. Charger le dashboard

```powershell
vagrant ssh obs -c "sudo systemctl restart grafana-server"
```
Ouvrir http://127.0.0.1:3000 et choisir le dossier **RÉSULTATS-BF**.

## 5. Démontrer le débit et la panne

1. Lancer un test de charge depuis PowerShell avec le script existant `tests\test-load.ps1` ou faire 30 requêtes :
```powershell
1..30 | ForEach-Object { Invoke-RestMethod "http://127.0.0.1:8080/info" | Out-Null }
```
2. Dans Grafana, observer « Requêtes HTTP / seconde » et « Débit de réponses par serveur applicatif ». La répartition par serveur nécessite que le backend HAProxy expose `haproxy_server_http_responses_total`.
3. Arrêter une VM applicative (ex. `app2`) :
```powershell
vagrant halt app2
```
4. Refaire le test de charge. Dans HAProxy, `app2` doit passer DOWN et les autres serveurs doivent continuer à recevoir des requêtes. Le panneau « État des serveurs HAProxy » doit refléter cet état après quelques secondes.
5. Remettre le serveur :
```powershell
vagrant up app2
```
Si nécessaire, attendre la fin du provisionnement puis vérifier `http://127.0.0.1:8080/sante`.

Important : `vagrant halt app2` arrête réellement la VM ; la remettre en service à la fin de la démonstration.

## Notes
- Les requêtes/s ne s'affichent qu'après génération de trafic et après au moins un intervalle de collecte.
- Si les métriques de débit ne sont pas présentes, consulter `http://127.0.0.1:9090/targets` et vérifier les métriques disponibles sur `http://127.0.0.1:8404/metrics`.
- Les panneaux système dépendent de Node Exporter sur chaque machine et de cibles `node` en état UP.
