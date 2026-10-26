"""API RESULTATS-BF : sans etat, tout l'etat vit dans PostgreSQL.
Cache Redis facultatif (E3) : une panne de Redis ne doit jamais casser le service."""
import json
import os
import socket

import psycopg2
import redis
from flask import Flask, jsonify, request

app = Flask(__name__)
E = os.environ
DSN = dict(host=E.get("DB_HOST", "127.0.0.1"), dbname=E.get("DB_NAME", "resultats"),
           user=E.get("DB_USER", ""), password=E.get("DB_PASSWORD", ""), connect_timeout=1)
TTL = int(E.get("CACHE_TTL", "60"))
CHAMPS = ("matricule", "nom", "serie", "moyenne", "admis")
_conn = _cache = None


def base():
    """Connexion creee a la demande : l'application demarre meme si la base est absente."""
    global _conn
    if _conn is None or _conn.closed:
        _conn = psycopg2.connect(**DSN)
        _conn.autocommit = True
    return _conn


def oublier():
    global _conn
    try:
        _conn.close()
    except (psycopg2.Error, AttributeError):
        pass
    _conn = None


def cache():
    global _cache
    if TTL <= 0 or not E.get("REDIS_HOST"):
        return None
    if _cache is None:
        _cache = redis.Redis(host=E["REDIS_HOST"], password=E.get("REDIS_PASSWORD") or None,
                             socket_timeout=0.3, socket_connect_timeout=0.3)
    return _cache


@app.route("/sante")
def sante():
    """200 si la base repond, 503 sinon. C'est la sonde de HAProxy."""
    try:
        cur = base().cursor()
        cur.execute("SELECT 1")
        cur.close()
        return jsonify(statut="ok")
    except psycopg2.Error:
        oublier()
        return jsonify(statut="base indisponible"), 503


@app.route("/info")
def info():
    return jsonify(hote=socket.gethostname())


@app.route("/resultat")
def resultat():
    matricule = request.args.get("matricule", "").strip()
    if not matricule:
        return jsonify(erreur="parametre matricule manquant"), 400
    cle, c = "resultat:" + matricule, cache()
    if c is not None:
        try:
            brut = c.get(cle)
            if brut:
                return app.response_class(brut, mimetype="application/json")
        except redis.RedisError:
            pass
    try:
        cur = base().cursor()
        cur.execute("SELECT matricule, nom, serie, moyenne, admis FROM resultats WHERE matricule = %s",
                    (matricule,))
        ligne = cur.fetchone()
        cur.close()
    except psycopg2.Error:
        oublier()
        return jsonify(erreur="base indisponible"), 503
    if ligne is None:
        return jsonify(erreur="matricule inconnu"), 404
    doc = dict(zip(CHAMPS, ligne))
    doc["moyenne"] = float(doc["moyenne"])
    corps = json.dumps(doc)
    if c is not None:
        try:
            c.setex(cle, TTL, corps)
        except redis.RedisError:
            pass
    return app.response_class(corps, mimetype="application/json")
