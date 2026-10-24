#!/usr/bin/env python3
"""Service RÉSULTATS-BF : sans état, tout l'état vit dans la base (/resultat, /sante, /info).
Arrêt en douceur (E4) : sur SIGTERM, /sante renvoie 503 pendant DRAIN_SECONDS (le répartiteur
écarte ce serveur), puis le service s'arrête : une mise à jour ne perd aucune requête."""
import json
import os
import signal
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import psycopg2

VERSION = "1.0"
PORT = int(os.environ.get("APP_PORT", "3000"))
HOTE = socket.gethostname()
DRAIN = int(os.environ.get("DRAIN_SECONDS", "5"))
ARRET = threading.Event()                   # levé à l'arrêt : cycle de vie, pas un état métier
DB = dict(
    host=os.environ["DB_HOST"],
    port=int(os.environ.get("DB_PORT", "5432")),
    dbname=os.environ.get("DB_NAME", "resultats"),
    user=os.environ["DB_USER"],
    password=os.environ["DB_PASSWORD"],
    connect_timeout=2,                      # base absente : on échoue vite
    options="-c statement_timeout=2000",
)
COLONNES = "matricule, nom, serie, moyenne, admis"


def interroger(sql, params=()):
    conn = psycopg2.connect(**DB)
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()
    finally:
        conn.close()


class Handler(BaseHTTPRequestHandler):
    def repondre(self, code, corps):
        data = json.dumps(corps, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def sante(self):
        if ARRET.is_set():
            return self.repondre(503, {"status": "arret en cours"})
        try:
            interroger("SELECT 1")
        except psycopg2.Error:
            return self.repondre(503, {"status": "base indisponible"})
        self.repondre(200, {"status": "ok"})

    def resultat(self, query):
        matricule = (query.get("matricule") or [""])[0].strip()
        if not matricule:
            return self.repondre(400, {"erreur": "parametre matricule manquant"})
        try:
            ligne = interroger(
                f"SELECT {COLONNES} FROM resultats WHERE matricule = %s", (matricule,))
        except psycopg2.Error:
            return self.repondre(503, {"erreur": "base indisponible"})
        if ligne is None:
            return self.repondre(404, {"erreur": "matricule inconnu"})
        self.repondre(200, {
            "matricule": ligne[0], "nom": ligne[1], "serie": ligne[2],
            "moyenne": float(ligne[3]), "admis": ligne[4],
        })

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/info":
            self.repondre(200, {"hote": HOTE, "version": VERSION})
        elif url.path == "/sante":
            self.sante()
        elif url.path == "/resultat":
            self.resultat(parse_qs(url.query))
        else:
            self.repondre(404, {"erreur": "introuvable"})

    def log_message(self, *args):           # silence : ne ralentit pas les tests de charge
        pass


if __name__ == "__main__":
    ThreadingHTTPServer.request_queue_size = 128   # supporte ab -c 50
    serveur = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)

    def arreter(*_):
        ARRET.set()
        threading.Timer(DRAIN, serveur.shutdown).start()
    signal.signal(signal.SIGTERM, arreter)
    serveur.serve_forever()