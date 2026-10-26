#!/usr/bin/env bash
# Répartiteur : HAProxy (config engendrée depuis noeuds.yml) + keepalived (E1).
# Rejouable à volonté : fichiers réécrits en entier, rechargement seulement si changement.
set -euo pipefail
cd /tmp
source /vagrant/scripts/lib.sh
NOEUDS=/vagrant/config/noeuds.yml
HOTE=$(hostname)
: "${NODE_IP:?NODE_IP manquant}" "${VIP:?VIP manquant}"

PAQUETS="haproxy apache2-utils"
[ "${LB2:-0}" = "1" ] && PAQUETS="$PAQUETS keepalived"
installer $PAQUETS

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# --- HAProxy : backend engendré à partir des nœuds de rôle "app" -----------
python3 - "$NOEUDS" > "$TMP/haproxy.cfg" <<'PY'
import sys, yaml
apps = [n for n in yaml.safe_load(open(sys.argv[1])) if n["role"] == "app"]
print("""# Fichier engendré par scripts/lb.sh depuis config/noeuds.yml - ne pas éditer
global
    log /dev/log local0
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    mode http
    log global
    option httplog
    option redispatch
    retries 2
    timeout connect 2s
    timeout client  10s
    timeout server  10s
    timeout check   1s

frontend http_in
    bind 0.0.0.0:80
    default_backend apps

backend apps
    balance roundrobin
    option httpchk
    http-check send meth GET uri /sante
    http-check expect status 200
    default-server inter 1s fall 2 rise 2""")
for n in apps:
    print(f'    server {n["nom"]} {n["ip"]}:3000 check')
print("""
listen stats
    bind 0.0.0.0:8404
    stats enable
    stats uri /
    stats refresh 2s""")
PY
haproxy -c -q -f "$TMP/haproxy.cfg"
CHANGE=0
if maj /etc/haproxy/haproxy.cfg "$TMP/haproxy.cfg"; then CHANGE=1; fi
systemctl enable haproxy >/dev/null 2>&1
if [ "$CHANGE" = 1 ] || ! systemctl is-active --quiet haproxy; then
  systemctl reload-or-restart haproxy
fi

# --- keepalived : IP virtuelle partagée en VRRP (E1) -----------------------
if [ "${LB2:-0}" = "1" ]; then
  IFACE=$(ip -o -4 addr show | awk -v ip="$NODE_IP" 'index($4, ip"/")==1 {print $2; exit}')
  [ -n "$IFACE" ] || { echo "Interface portant $NODE_IP introuvable" >&2; exit 1; }
  PAIR=$(python3 - "$NOEUDS" "$HOTE" <<'PY'
import sys, yaml
lbs = [n for n in yaml.safe_load(open(sys.argv[1])) if n["role"] == "lb" and n["nom"] != sys.argv[2]]
print(lbs[0]["ip"])
PY
)
  if [ "$HOTE" = "lb1" ]; then ETAT=MASTER; PRIO=150; else ETAT=BACKUP; PRIO=100; fi
  cat > "$TMP/keepalived.conf" <<EOFK
# Fichier engendré par scripts/lb.sh - ne pas éditer
global_defs {
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/pidof haproxy"
    interval 1
    fall 2
    rise 2
}

vrrp_instance VI_RESULTATS {
    state $ETAT
    interface $IFACE
    virtual_router_id $((50 + ${GROUPE:-1}))
    priority $PRIO
    advert_int 1
    unicast_src_ip $NODE_IP
    unicast_peer {
        $PAIR
    }
    virtual_ipaddress {
        $VIP/24 dev $IFACE
    }
    track_script {
        chk_haproxy
    }
}
EOFK
  KCHANGE=0
  if maj /etc/keepalived/keepalived.conf "$TMP/keepalived.conf"; then KCHANGE=1; fi
  systemctl enable keepalived >/dev/null 2>&1
  if [ "$KCHANGE" = 1 ] || ! systemctl is-active --quiet keepalived; then
    systemctl restart keepalived
  fi
else
  systemctl disable --now keepalived >/dev/null 2>&1 || true
fi
