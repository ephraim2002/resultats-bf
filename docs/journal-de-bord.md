---PAGE---
JOURNAL DE BORD DU PROJET
RÉSULTATS-BF — GROUPE 18

Université Joseph KI-ZERBO (UJKZ) · Institut Burkinabè des Arts et Métiers (IBAM)
Master 1 Informatique — Virtualisation et Cloud Computing
Année universitaire 2026–2027
Enseignant : Dr SOMDA Flavien Hervé

[Emplacement pour le logo officiel IBAM]                [Emplacement pour le logo officiel UJKZ]

Dépôt : https://github.com/ephraim2002/resultats-bf
Date du compte rendu : 27 octobre 2026

ÉQUIPE — QUATRE MEMBRES

| Nom | Prénom | Numéro | Filière |
|---|---|---|---|
| BARRY | El Nour | 66806583 | SI |
| BAMBARA | Mireille Epiphanie Joëlle Guerla | 6539632 | SIE |
| SAWADOGO | Wenden Kogondé Aimé Ephraïm | 72620579 | SI |
| WEDRAOGO | Relwende Diane Micheline | 76677438 | SIE |

Note : les logos officiels ne sont pas inclus dans les fichiers du dépôt ou du sujet transmis ; les emplacements ci-dessus sont à compléter avec les fichiers autorisés par l’IBAM et l’UJKZ avant transmission au professeur.
---PAGE---
JOURNAL DES TRAVAUX ET BILAN DE VALIDATION

1. Objet et réalisation
Le groupe 18 a conçu RÉSULTATS-BF, une plateforme pédagogique de consultation de résultats scolaires destinée à étudier la virtualisation, la répartition de charge, la réplication et la supervision. Le projet prévoit jusqu’à quatre serveurs applicatifs configurables par NB_APP. Pour respecter les ressources mémoire disponibles sur le poste de travail, l’équipe a volontairement limité l’environnement de cette campagne à deux applications (app1 et app2) ; ce choix pratique ne réduit pas la capacité cible du projet. Le dépôt assemble Vagrant/VirtualBox, des API Flask exécutées par Gunicorn, PostgreSQL, HAProxy/Keepalived et Prometheus/Grafana. Les quatre domaines de contribution sont identifiés dans le dossier d’architecture ; les noms des responsables doivent être confirmés par le groupe, car aucun relevé disponible ne permet de les attribuer sans supposition.

2. Vérifications de l’environnement — 27 octobre 2026
`vagrant validate` a réussi. Le relevé a indiqué sept VM en fonctionnement : bdd1, bdd2, app1, app2, lb1, lb2 et obs. Les variables actives étaient NB_APP=2, ENABLE_HA=true et ENABLE_OBS=true ; les deux applications étaient le dimensionnement choisi pour respecter les ressources du poste, alors que le Vagrantfile permet d’en provisionner jusqu’à quatre. Sur un poste plus puissant, les quatre instances prévues peuvent être activées en fixant NB_APP=4. Les contrôles HTTP en lecture seule ont donné HTTP 200 à `/info` et `/sante`, via `localhost:8080` et la VIP `192.168.63.10`. La recherche du matricule de test MAT000001 a retourné la ligne attendue.

Les vérifications SQL ont compté 50 000 lignes sur chacune des bases. bdd2 était en récupération ; l’état primaire-réplica était `streaming` et les LSN envoyé/rejoué concordaient au moment de la mesure. Ces vérifications sont des instantanés, pas un essai de bascule.

3. Mesure de répartition et traces
Sur 200 appels séquentiels à `/info`, app1 a répondu 100 fois et app2 100 fois. Aucune erreur n’a été relevée ; le chronométrage global était de 2,331 s, soit 85,8 réponses/s et une différence de répartition de 0 %. Ce résultat concerne une route légère, sans accès SQL, et ne mesure ni 2 000 requêtes concurrentes ni la capacité lorsque quatre applications tournent simultanément. Ces deux nœuds supplémentaires sont prévus dans le projet, mais n’ont pas été lancés sur ce poste en raison de ses ressources.

Le CSV historique `v2-20261027-195118.csv` contient 387 échantillons sur environ 60 s : 385 HTTP 200 lisibles (app1=97, app2=288), une absence de réponse et un HTTP 502. Il témoigne d’un déséquilibre et de deux erreurs, mais ne prouve pas seul la cause ni la durée d’une panne. Un autre relevé applicatif, sans répartiteur, rapporte 3 erreurs sur 913 requêtes pendant un redémarrage doux (0,3 %).

4. Supervision, limites et suite
Prometheus était prêt avec 12 cibles actives : 10 « up » et deux « down » (Node Exporter d’app3/app4). Ces deux applications appartiennent à la capacité prévue à quatre, mais avaient été volontairement laissées arrêtées car la mémoire du poste ne permettait pas de retenir la configuration complète pendant cette campagne. Les deux états « down » reflètent donc le dimensionnement temporaire NB_APP=2, et non une limite fonctionnelle du projet. Grafana indiquait `database=ok` (version 13.2.4), mais l’API anonyme de recherche retournait HTTP 401 ; les dashboards n’ont donc pas été contrôlés avec une session authentifiée.

V1 est mesuré sur 200 appels, pas sur les 20 demandés. V2 reste historique/partiel ; le benchmark concurrent V3, la promotion bdd2 (V4), la reconstruction sur poste vierge (V5) et la panne du répartiteur avec maintien de VIP (V6) ne sont pas démontrés. Ils nécessitent sauvegarde, autorisation de l’équipe et rapports horodatés. Avant remise, confirmer les rôles nominatifs, ajouter les logos officiels autorisés, vérifier les secrets sans en publier les valeurs et compléter les essais possibles sans présenter les scénarios non exécutés comme des réussites.
