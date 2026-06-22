#!/data/data/com.termux/files/usr/bin/bash
# OpenCode Termux Setup Script
# Run this in Termux on Android to install opencode

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  OpenCode Termux Setup${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "${YELLOW}[1/5] Updating packages...${NC}"
pkg update -y && pkg upgrade -y

echo -e "${YELLOW}[2/5] Installing dependencies...${NC}"
pkg install -y nodejs-lts git curl wget python openssh

echo -e "${YELLOW}[3/5] Installing opencode via npm...${NC}"
npm install -g opencode-ai

echo -e "${YELLOW}[4/5] Verifying installation...${NC}"
if command -v opencode &> /dev/null; then
    echo -e "${GREEN}opencode version: $(opencode --version)${NC}"
else
    echo -e "${RED}opencode not found in PATH after install${NC}"
    echo -e "${YELLOW}Trying alternative install method...${NC}"
    npm install -g @opencode-ai/opencode
fi

echo -e "${YELLOW}[5/5] Creating start script...${NC}"
START_SCRIPT="$HOME/.opencode/start.sh"

mkdir -p "$HOME/.opencode"

cat > "$START_SCRIPT" << 'SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

echo "Starting OpenCode Serve on port 4096..."
echo "Access from OpenCode Mobile app at: http://localhost:4096"
echo ""

cd "$HOME"
opencode serve --port 4096 --hostname 127.0.0.1 --cors "*"
SCRIPT

chmod +x "$START_SCRIPT"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "To start opencode server, run:"
echo -e "  ${YELLOW}bash ~/.opencode/start.sh${NC}"
echo ""
echo -e "Or manually:"
echo -e "  ${YELLOW}opencode serve --port 4096 --hostname 127.0.0.1${NC}"
echo ""
echo -e "Then open OpenCode Mobile app and connect to:"
echo -e "  ${YELLOW}http://localhost:4096${NC}"
echo ""
echo -e "${YELLOW} NOTE: If you want to access from other devices on your network,${NC}"
echo -e "${YELLOW} use --hostname 0.0.0.0 instead and connect to your phone's IP.${NC}"
