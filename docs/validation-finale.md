# RÉSULTATS-BF — Validation finale

## Architecture
- Virtualisation : VirtualBox et Vagrant
- Réseau privé : 192.168.63.0/24
- Bases : bdd1 (primaire), bdd2 (réplique PostgreSQL)
- Applications : app1, app2, app3, app4
- Répartiteurs : lb1, lb2
- Adresse virtuelle : 192.168.63.10
- Accès de démonstration local : http://127.0.0.1:8080

## Tests à documenter
- [ ] vagrant validate
- [ ] Toutes les machines sont running
- [ ] API /sante retourne HTTP 200
- [ ] Recherche d'un matricule fonctionnelle
- [ ] Répartition observée sur plusieurs applications
- [ ] Réplication PostgreSQL en état streaming
- [ ] 50 000 résultats présents sur la réplique
- [ ] VIP disponible après arrêt de lb1
- [ ] Retour de lb1 après redémarrage
- [ ] Configuration à quatre applications opérationnelle

## Limites connues à signaler
- Le basculement PostgreSQL nécessite une promotion contrôlée de bdd2.
- La promotion de bdd2 ne met pas automatiquement à jour DB_HOST sur les applications.
- L'observabilité Prometheus reste à valider séparément si elle est exigée dans le cahier des charges.
