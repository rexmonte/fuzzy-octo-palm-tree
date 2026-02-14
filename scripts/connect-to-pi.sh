#!/bin/bash
# connect-to-pi.sh — Diagnose and connect Mac Mini to Raspberry Pi gateway
# Run this ON THE MAC MINI to test connectivity and launch node host.
#
# Usage:
#   ./connect-to-pi.sh check                    — run diagnostics only
#   ./connect-to-pi.sh connect                  — connect as node host
#   ./connect-to-pi.sh connect 192.168.0.XXX    — connect using specific IP
#   ./connect-to-pi.sh tunnel <pi-user> <pi-ip> — SSH tunnel approach

set -euo pipefail

PI_HOSTNAME="${PI_HOSTNAME:-raspberrypi.local}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18790}"
MODE="${1:-check}"

log()  { echo "[connect-to-pi] $1"; }
ok()   { echo "[connect-to-pi] ✅ $1"; }
warn() { echo "[connect-to-pi] ⚠️  $1"; }
fail() { echo "[connect-to-pi] ❌ $1"; }

# --- Diagnostics ---

resolve_pi() {
    log "Resolving Pi hostname: $PI_HOSTNAME"

    # Try mDNS resolution
    if PI_IP=$(getent hosts "$PI_HOSTNAME" 2>/dev/null | awk '{print $1}' | head -1) && [ -n "$PI_IP" ]; then
        ok "$PI_HOSTNAME → $PI_IP"
        echo "$PI_IP"
        return 0
    fi

    # Try dns-sd on macOS
    if command -v dns-sd &>/dev/null; then
        log "Trying Bonjour discovery..."
        # dns-sd is interactive so we timeout after 3 seconds
        PI_IP=$(timeout 3 dns-sd -G v4 "$PI_HOSTNAME" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1) || true
        if [ -n "$PI_IP" ]; then
            ok "$PI_HOSTNAME → $PI_IP (via Bonjour)"
            echo "$PI_IP"
            return 0
        fi
    fi

    # Try ping
    if PI_IP=$(ping -c 1 -W 3 "$PI_HOSTNAME" 2>/dev/null | head -1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1) && [ -n "$PI_IP" ]; then
        ok "$PI_HOSTNAME → $PI_IP (via ping)"
        echo "$PI_IP"
        return 0
    fi

    fail "Cannot resolve $PI_HOSTNAME"
    echo ""
    log "Troubleshooting:"
    echo "  1. Make sure the Pi is powered on and on the same network"
    echo "  2. Check Pi's avahi-daemon: systemctl status avahi-daemon"
    echo "  3. Check Pi's hostname: hostname (on the Pi)"
    echo "  4. Find Pi's IP from your router's admin page"
    echo "  5. Try the IP directly: $0 connect <PI_IP_ADDRESS>"
    return 1
}

check_connectivity() {
    local TARGET_IP="$1"
    log "Testing connectivity to $TARGET_IP..."

    # Ping test
    if ping -c 1 -W 3 "$TARGET_IP" &>/dev/null; then
        ok "Ping successful"
    else
        fail "Ping failed — Pi may be offline or on a different network"
        return 1
    fi

    # Port test
    log "Testing gateway port $GATEWAY_PORT..."
    if nc -zv -w 5 "$TARGET_IP" "$GATEWAY_PORT" 2>&1; then
        ok "Gateway port $GATEWAY_PORT is reachable"
    else
        fail "Gateway port $GATEWAY_PORT is NOT reachable"
        echo ""
        log "This means either:"
        echo "  1. Gateway is not running on the Pi"
        echo "  2. Gateway is bound to loopback (127.0.0.1) only"
        echo "  3. Docker is not mapping the port to the host"
        echo "  4. A firewall is blocking the port"
        echo ""
        echo "  Fix: Run expose-gateway-lan.sh on the Pi"
        echo "  Or use SSH tunnel: $0 tunnel <pi-user> $TARGET_IP"
        return 1
    fi
}

run_diagnostics() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Mac Mini → Raspberry Pi Connection Diagnostic"
    echo "  Target: $PI_HOSTNAME:$GATEWAY_PORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check local OpenClaw
    log "Checking local OpenClaw installation..."
    if command -v openclaw &>/dev/null; then
        OCVERSION=$(openclaw --version 2>/dev/null || echo "unknown")
        ok "OpenClaw installed: $OCVERSION"
    else
        fail "OpenClaw not found in PATH"
        return 1
    fi

    echo ""

    # Resolve hostname
    PI_IP=$(resolve_pi) || return 1
    echo ""

    # Test connectivity
    check_connectivity "$PI_IP" || return 1

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ok "All checks passed! Ready to connect."
    echo ""
    log "Connect with:"
    echo "  openclaw node run --host $PI_IP --port $GATEWAY_PORT"
    echo ""
    log "Or run:"
    echo "  $0 connect $PI_IP"
}

# --- Connection modes ---

connect_direct() {
    local TARGET="${2:-}"

    if [ -z "$TARGET" ]; then
        log "Resolving Pi..."
        TARGET=$(resolve_pi) || exit 1
    fi

    log "Connecting to Pi gateway at $TARGET:$GATEWAY_PORT..."
    echo ""
    exec openclaw node run --host "$TARGET" --port "$GATEWAY_PORT"
}

connect_tunnel() {
    local PI_USER="${2:-}"
    local PI_IP="${3:-}"

    if [ -z "$PI_USER" ] || [ -z "$PI_IP" ]; then
        echo "Usage: $0 tunnel <pi-user> <pi-ip>"
        echo "Example: $0 tunnel pi 192.168.0.50"
        exit 1
    fi

    log "Creating SSH tunnel to $PI_USER@$PI_IP..."
    log "Forwarding localhost:$GATEWAY_PORT → Pi:$GATEWAY_PORT"
    echo ""
    log "Keep this terminal open. In a NEW terminal, run:"
    echo "  openclaw node run --host 127.0.0.1 --port $GATEWAY_PORT"
    echo ""

    ssh -N -L "$GATEWAY_PORT:127.0.0.1:$GATEWAY_PORT" "$PI_USER@$PI_IP"
}

# --- Main ---

case "$MODE" in
    check)
        run_diagnostics
        ;;
    connect)
        connect_direct "$@"
        ;;
    tunnel)
        connect_tunnel "$@"
        ;;
    *)
        echo "Usage: $0 [check|connect [ip]|tunnel <user> <ip>]"
        echo ""
        echo "Commands:"
        echo "  check              Run connectivity diagnostics"
        echo "  connect            Connect as node host (auto-resolve Pi)"
        echo "  connect <ip>       Connect as node host to specific IP"
        echo "  tunnel <user> <ip> Create SSH tunnel then connect"
        echo ""
        echo "Environment variables:"
        echo "  PI_HOSTNAME              Pi hostname (default: raspberrypi.local)"
        echo "  OPENCLAW_GATEWAY_PORT    Gateway port (default: 18790)"
        exit 1
        ;;
esac
