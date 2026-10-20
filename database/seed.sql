INSERT INTO resultats (matricule, nom, serie, moyenne, admis)
SELECT
    'MAT' || LPAD(g::TEXT, 6, '0'),
    'Eleve_' || LPAD(g::TEXT, 6, '0'),
    CASE (g % 4)
        WHEN 0 THEN 'A'
        WHEN 1 THEN 'C'
        WHEN 2 THEN 'D'
        ELSE 'H'
    END,
    ROUND((5 + ((g * 37) % 1501) / 100.0)::NUMERIC, 2),
    (5 + ((g * 37) % 1501) / 100.0) >= 10
FROM generate_series(1, 50000) AS g
ON CONFLICT (matricule) DO NOTHING;
