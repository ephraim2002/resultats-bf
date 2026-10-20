#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        echo "Variable obligatoire absente : ${name}" >&2
        exit 1
    fi
}

wait_for_postgres() {
    local host="$1"
    local port="${2:-5432}"
    local attempts="${3:-60}"

    for ((i=1; i<=attempts; i++)); do
        if pg_isready -h "$host" -p "$port" >/dev/null 2>&1; then
            log "PostgreSQL répond sur ${host}:${port}"
            return 0
        fi
        sleep 2
    done

    echo "PostgreSQL ne répond pas sur ${host}:${port}" >&2
    return 1
}