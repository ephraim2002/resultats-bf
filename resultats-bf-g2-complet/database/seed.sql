-- 50 000 lignes deterministes (BF000001 a BF050000), inserees seulement si la table est vide.
INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT 'BF' || lpad(g::text, 6, '0'),
       'Candidat ' || g,
       (ARRAY['A','C','D','E','F','G','H'])[1 + g % 7],
       round(((g * 7919) % 2001) / 100.0, 2),
       ((g * 7919) % 2001) >= 1000
FROM generate_series(1, 50000) AS g
WHERE NOT EXISTS (SELECT 1 FROM resultats);
