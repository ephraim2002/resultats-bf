#!/usr/bin/env bash
set -Eeuo pipefail

source /vagrant/scripts/common.sh
: "${LB_PRIORITY:?LB_PRIORITY doit être défini}"

# Installer/configurer HAProxy avec le script déjà présent.
bash /vagrant/scripts/setup-lb.sh

export DEBIAN_FRONTEND=noninteractive
apt-get install -y keepalived

LOCAL_IP="$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.63\.(11|12)\// {split($4,a,"/"); print a[1]}')"
IFACE="$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.63\.(11|12)\// {print $2}')"

if [[ "$LOCAL_IP" == "192.168.63.11" ]]; then
    PEER_IP="192.168.63.12"
elif [[ "$LOCAL_IP" == "192.168.63.12" ]]; then
    PEER_IP="192.168.63.11"
else
    echo "Impossible de déterminer l'adresse privée du load balancer." >&2
    exit 1
fi

if [[ -z "$IFACE" ]]; then
    echo "Interface réseau privée introuvable." >&2
    exit 1
fi

cat > /etc/keepalived/keepalived.conf <<EOF
global_defs {
    router_id ${LOCAL_IP//./_}
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/usr/bin/pgrep haproxy"
    interval 2
    timeout 2
    fall 2
    rise 2
    weight -20
}

vrrp_instance VI_RESULTATS {
    state BACKUP
    interface ${IFACE}
    virtual_router_id 63
    priority ${LB_PRIORITY}
    advert_int 1

    unicast_src_ip ${LOCAL_IP}
    unicast_peer {
        ${PEER_IP}
    }

    authentication {
        auth_type PASS
        auth_pass R3sBF63
    }

    virtual_ipaddress {
        192.168.63.10/24 dev ${IFACE}
    }

    track_script {
        chk_haproxy
    }
}
EOF

keepalived -t -f /etc/keepalived/keepalived.conf
systemctl enable keepalived
systemctl restart keepalived

log "HAProxy et Keepalived configurés sur ${LOCAL_IP}, priorité ${LB_PRIORITY}"