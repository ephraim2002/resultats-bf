import os
import socket

import psycopg2
from flask import Flask, jsonify, request
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST", "192.168.63.31")
DB_NAME = os.getenv("DB_NAME", "resultats")
DB_USER = os.getenv("DB_USER", "resultats_app")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=2,
    )


@app.get("/sante")
def sante():
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        return jsonify({"statut": "ok", "base": "accessible"}), 200
    except Exception:
        return jsonify({"statut": "indisponible", "base": "inaccessible"}), 503


@app.get("/info")
def info():
    return jsonify({
        "machine": socket.gethostname(),
        "service": "resultats-bf-api"
    }), 200


@app.get("/resultat")
def resultat():
    matricule = request.args.get("matricule", "").strip()

    if not matricule:
        return jsonify({"erreur": "Le parametre matricule est obligatoire"}), 400

    try:
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT matricule, nom, serie, moyenne, admis
                    FROM resultats
                    WHERE matricule = %s
                    """,
                    (matricule,),
                )
                row = cur.fetchone()

        if row is None:
            return jsonify({"erreur": "Resultat introuvable"}), 404

        return jsonify(dict(row)), 200

    except Exception:
        app.logger.exception("Erreur lors de la lecture des resultats")
        return jsonify({"erreur": "Base de donnees indisponible"}), 503


@app.get("/")
def accueil():
    return jsonify({
        "projet": "RESULTATS-BF",
        "endpoints": ["/sante", "/info", "/resultat?matricule=MAT000001"]
    }), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
