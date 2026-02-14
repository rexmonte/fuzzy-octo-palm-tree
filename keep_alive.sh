#!/bin/bash
# keep_alive.sh — Monitor Mac Mini OpenClaw + Pi gateway connectivity
# Run via cron: */5 * * * * /path/to/keep_alive.sh >> /path/to/keep_alive.log 2>&1

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOGFILE="${DIR}/keep_alive.log"
PI_HOSTNAME="${PI_HOSTNAME:-umbrel.local}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18790}"
CONNECT_SCRIPT="${DIR}/scripts/connect-to-pi.sh"

log()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"; }

# --- Check 1: Local OpenClaw gateway process ---
check_local_gateway() {
    if pgrep -f "openclaw gateway" > /dev/null 2>&1 || pgrep -f "openclaw-gateway" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# --- Check 2: Pi gateway reachable over network ---
check_pi_reachable() {
    # Resolve Pi hostname to IP
    local PI_IP
    PI_IP=$(getent hosts "$PI_HOSTNAME" 2>/dev/null | awk '{print $1}' | head -1)
    if [ -z "$PI_IP" ]; then
        PI_IP=$(ping -c 1 -W 3 "$PI_HOSTNAME" 2>/dev/null | head -1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi

    if [ -z "$PI_IP" ]; then
        log "WARN: Cannot resolve $PI_HOSTNAME"
        return 1
    fi

    # Check if gateway port is open
    if nc -zw5 "$PI_IP" "$GATEWAY_PORT" 2>/dev/null; then
        return 0
    fi
    return 1
}

# --- Check 3: Node host process running (connected to Pi) ---
check_node_connection() {
    if pgrep -f "openclaw node run" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

# --- Recovery ---
restart_local_gateway() {
    log "Restarting local OpenClaw gateway..."
    openclaw gateway restart >> "$LOGFILE" 2>&1 || {
        log "openclaw gateway restart failed — trying process restart"
        pkill -f "openclaw" 2>/dev/null || true
        sleep 3
        nohup openclaw &>> "$LOGFILE" &
    }
    sleep 5
}

restart_node_connection() {
    log "Restarting node connection to Pi..."
    # Kill any existing stale node connection
    pkill -f "openclaw node run" 2>/dev/null || true
    sleep 2

    # Resolve Pi
    local PI_IP
    PI_IP=$(getent hosts "$PI_HOSTNAME" 2>/dev/null | awk '{print $1}' | head -1)
    if [ -z "$PI_IP" ]; then
        PI_IP=$(ping -c 1 -W 3 "$PI_HOSTNAME" 2>/dev/null | head -1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    fi

    if [ -z "$PI_IP" ]; then
        log "ERROR: Cannot resolve Pi — node connection not restarted"
        return 1
    fi

    # Start node connection in background
    nohup openclaw node run --host "$PI_IP" --port "$GATEWAY_PORT" &>> "$LOGFILE" &
    sleep 5

    if check_node_connection; then
        log "OK: Node connection re-established to $PI_IP:$GATEWAY_PORT"
    else
        log "ERROR: Node connection failed to restart"
        return 1
    fi
}

# --- Main ---
main() {
    # Local gateway
    if check_local_gateway; then
        log "OK: Local gateway running"
    else
        log "WARN: Local gateway down — restarting"
        restart_local_gateway
        if check_local_gateway; then
            log "OK: Local gateway recovered"
        else
            log "ERROR: Local gateway recovery FAILED"
        fi
    fi

    # Pi reachability
    if check_pi_reachable; then
        log "OK: Pi gateway reachable at $PI_HOSTNAME:$GATEWAY_PORT"

        # Node connection (only matters if Pi is reachable)
        if check_node_connection; then
            log "OK: Node connection active"
        else
            log "WARN: Node connection down — Pi is reachable, restarting node"
            restart_node_connection
        fi
    else
        log "WARN: Pi gateway not reachable at $PI_HOSTNAME:$GATEWAY_PORT"
        log "  - Is the Pi on? Is the gateway exposed on LAN?"
        log "  - Run on Pi: /data/.openclaw/workspace/scripts/expose-gateway-lan.sh fix-all"
    fi
}

main
