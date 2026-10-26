#!/usr/bin/env bash
# Test de charge Apache Bench, lancé depuis lb1 : charge.sh [requêtes] [concurrence] [matricule]
exec ab -n "${1:-2000}" -c "${2:-50}" -q "http://127.0.0.1/resultat?matricule=${3:-BF000042}"
