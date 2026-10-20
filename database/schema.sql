CREATE TABLE IF NOT EXISTS resultats (
    matricule VARCHAR(20) PRIMARY KEY,
    nom VARCHAR(100) NOT NULL,
    serie VARCHAR(20) NOT NULL,
    moyenne NUMERIC(4,2) NOT NULL CHECK (moyenne >= 0 AND moyenne <= 20),
    admis BOOLEAN NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_resultats_serie
ON resultats (serie);
