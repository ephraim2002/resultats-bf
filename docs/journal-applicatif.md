&#x09;

|Test (service seul, sans répartiteur)|Résultat|
|-|-|
|Charge de base, 3 threads, 25 à 40 s|481, 617 puis 993 requêtes, 0 erreur, 19 à 25 req/s|
|Redémarrage en douceur pendant la charge |	913 requêtes, 3 erreurs (0,3 %), toutes dans une seule seconde, une par thread|
|Durée du drainage observée (journalctl)|5 s entre Stopping et Stopped, Started dans la même seconde|



Notez aussi la limite honnête : sans répartiteur, un redémarrage laisse un trou d’environ une seconde. L’objectif « aucune requête en erreur » de l’extension E4 se démontrera avec le répartiteur et deux serveurs, après la fusion.

