CREATE TABLE IF NOT EXISTS resultats (
    matricule text PRIMARY KEY,
    nom       text NOT NULL,
    serie     text NOT NULL,
    moyenne   numeric(4,2) NOT NULL,
    admis     boolean NOT NULL
);
