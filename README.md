# Mac Mini M4 - Home Server Infrastructure
## Role
Primary AI Gateway and Automation Hub. Connects to Raspberry Pi as a node host for distributed compute.

## Services
- **OpenClaw**: Autonomous agent running on port 18789.
- **Ollama**: Local inference (GLM-4.7-Flash).

## Connecting to Raspberry Pi Gateway

The Mac Mini runs as a **node host** connected to the Pi's OpenClaw gateway. The Pi is the always-on relay; the Mini provides local inference horsepower.

### Quick Start
```bash
# Diagnose connectivity first
./scripts/connect-to-pi.sh check

# Connect as node host (auto-resolves Pi)
./scripts/connect-to-pi.sh connect

# Or connect to a specific IP
./scripts/connect-to-pi.sh connect 192.168.0.XXX

# Or use SSH tunnel if gateway isn't exposed on LAN
./scripts/connect-to-pi.sh tunnel pi 192.168.0.XXX
```

### Common Issues

**`ENOTFOUND umbrel.local`** — Pi hostname can't be resolved via mDNS.
- Ensure avahi-daemon is running on the Pi: `sudo systemctl enable --now avahi-daemon`
- Or use the Pi's IP address directly instead of the hostname

**`ETIMEDOUT`** — Pi is reachable but gateway port isn't exposed.
- The Pi gateway likely binds to loopback (127.0.0.1) inside Docker
- Run `expose-gateway-lan.sh` on the Pi, or use the SSH tunnel approach

**Wrong port** — The Pi gateway listens on port **18790**, not 3000.

## Scripts
- `keep_alive.sh` — Cron-friendly health check: restarts OpenClaw gateway if it goes down.
- `scripts/connect-to-pi.sh` — Diagnose and connect to the Raspberry Pi gateway as a node host.
