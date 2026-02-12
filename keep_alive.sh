#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if ! pgrep -f "openclaw gateway" > /dev/null; then
    echo "$(date): OpenClaw down. Restarting..."
    openclaw gateway restart >> "$DIR/restart.log" 2>&1
fi
