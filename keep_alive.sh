#!/bin/bash
# OpenClaw Keep-Alive — checks process AND port, restarts if needed
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOGFILE="$DIR/restart.log"
GATEWAY_PORT=18789

log() {
    echo "$(date): $1" >> "$LOGFILE"
}

# Check if the gateway process is running AND responding on the correct port
gateway_healthy() {
    pgrep -f "openclaw gateway" > /dev/null 2>&1 || return 1
    curl -sf --max-time 5 "http://localhost:${GATEWAY_PORT}/health" > /dev/null 2>&1 || \
    curl -sf --max-time 5 "http://localhost:${GATEWAY_PORT}/" > /dev/null 2>&1 || return 1
    return 0
}

if ! gateway_healthy; then
    log "OpenClaw down or not responding on port ${GATEWAY_PORT}. Restarting..."
    if openclaw gateway restart >> "$LOGFILE" 2>&1; then
        sleep 5
        if gateway_healthy; then
            log "Restart successful — gateway responding on port ${GATEWAY_PORT}"
        else
            log "WARNING: Restart command succeeded but gateway not responding on port ${GATEWAY_PORT}"
        fi
    else
        log "ERROR: Restart command failed (exit code $?)"
    fi
fi
