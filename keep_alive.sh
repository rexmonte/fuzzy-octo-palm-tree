#!/bin/bash
# OpenClaw Keep-Alive for Mac Mini M4
# Checks if gateway process is running AND responding on port, restarts if needed
# Intended to run via cron (e.g., every 5 minutes)
set -uo pipefail

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

if gateway_healthy; then
    exit 0
fi

log "OpenClaw down or not responding on port ${GATEWAY_PORT}. Restarting..."

# Try openclaw gateway restart first
if command -v openclaw > /dev/null 2>&1; then
    openclaw gateway restart >> "$LOGFILE" 2>&1
    rc=$?
else
    log "ERROR: openclaw command not found in PATH"
    exit 1
fi

if [ $rc -ne 0 ]; then
    log "ERROR: Restart command failed (exit code $rc)"
    exit 1
fi

sleep 5

if gateway_healthy; then
    log "Restart successful — gateway responding on port ${GATEWAY_PORT}"
    exit 0
else
    log "WARNING: Restart command succeeded but gateway not responding on port ${GATEWAY_PORT}"
    exit 1
fi
