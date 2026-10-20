#!/usr/bin/env bash
set -Eeuo pipefail

source /vagrant/scripts/common.sh

NB_APP="${NB_APP:-2}"

if (( NB_APP < 2 || NB_APP > 4 )); then
    echo "NB_APP doit être compris entre 2 et 4." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y haproxy curl

install -d -m 755 /etc/haproxy

cat > /etc/haproxy/haproxy.cfg <<'HAPROXY'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 2048

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 3s
    timeout client 30s
    timeout server 30s

frontend resultats_frontend
    bind *:80
    default_backend resultats_apps

backend resultats_apps
    balance roundrobin
    option httpchk GET /sante
    http-check expect status 200
    default-server inter 1s fall 2 rise 2
HAPROXY

for i in $(seq 1 "$NB_APP"); do
    printf '    server app%s 192.168.63.%s:5000 check\n' \
        "$i" "$((20 + i))" >> /etc/haproxy/haproxy.cfg
done

haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl enable haproxy
systemctl restart haproxy

log "HAProxy configuré pour ${NB_APP} applications"