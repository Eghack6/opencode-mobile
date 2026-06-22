#!/data/data/com.termux/files/usr/bin/bash
# Start OpenCode server for mobile app connection
# Usage: ./start_opencode.sh [--host HOSTNAME] [--port PORT]

PORT=4096
HOSTNAME="127.0.0.1"

while [[ $# -gt 0 ]]; do
    case $1 in
        --host) HOSTNAME="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "========================================"
echo "  OpenCode Serve"
echo "========================================"
echo "  Host: $HOSTNAME"
echo "  Port: $PORT"
echo "  URL:  http://$HOSTNAME:$PORT"
echo "========================================"
echo ""
echo "Connect from OpenCode Mobile app using the URL above."
echo ""

opencode serve --port "$PORT" --hostname "$HOSTNAME"
