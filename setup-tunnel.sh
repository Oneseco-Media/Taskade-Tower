#!/usr/bin/env bash
# =============================================================================
# Cloudflare Tunnel setup for Taskade-Tower on macOS
# Run once on your Mac: bash setup-tunnel.sh
# =============================================================================
set -euo pipefail

TUNNEL_NAME="taskade-tower"
DOMAIN="oneseco.xyz"
LOCAL_PORT=3000
CLOUDFLARED_CONFIG="$HOME/.cloudflared/config.yml"
PLIST_PATH="$HOME/Library/LaunchAgents/com.taskade-tower.tunnel.plist"

echo "==> Checking for Homebrew..."
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

echo "==> Installing cloudflared..."
brew install cloudflare/cloudflare/cloudflared 2>/dev/null || brew upgrade cloudflare/cloudflare/cloudflared

echo ""
echo "==> Logging in to Cloudflare (browser will open)..."
cloudflared tunnel login

echo ""
echo "==> Creating tunnel '$TUNNEL_NAME'..."
# Capture tunnel ID from output
TUNNEL_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
echo "$TUNNEL_OUTPUT"
TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

if [ -z "$TUNNEL_ID" ]; then
  # Tunnel may already exist — retrieve existing ID
  TUNNEL_ID=$(cloudflared tunnel info "$TUNNEL_NAME" 2>/dev/null | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
fi

echo ""
echo "==> Tunnel ID: $TUNNEL_ID"

echo ""
echo "==> Writing cloudflared config to $CLOUDFLARED_CONFIG..."
mkdir -p "$HOME/.cloudflared"
cat > "$CLOUDFLARED_CONFIG" <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $HOME/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    service: http://localhost:$LOCAL_PORT
  - hostname: www.$DOMAIN
    service: http://localhost:$LOCAL_PORT
  - service: http_status:404
EOF

echo ""
echo "==> Routing DNS: $DOMAIN -> tunnel $TUNNEL_NAME"
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"
cloudflared tunnel route dns "$TUNNEL_NAME" "www.$DOMAIN"

echo ""
echo "==> Installing macOS Launch Agent (auto-start on login)..."
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.taskade-tower.tunnel</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/cloudflared</string>
    <string>tunnel</string>
    <string>--config</string>
    <string>$CLOUDFLARED_CONFIG</string>
    <string>run</string>
    <string>$TUNNEL_NAME</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/.cloudflared/tunnel.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/.cloudflared/tunnel-error.log</string>
</dict>
</plist>
EOF

launchctl load "$PLIST_PATH"

echo ""
echo "======================================================"
echo " Cloudflare Tunnel is running!"
echo " Public URL : https://$DOMAIN"
echo " Local port : http://localhost:$LOCAL_PORT"
echo " Tunnel ID  : $TUNNEL_ID"
echo " Notion OAuth redirect URI is already set to https://$DOMAIN"
echo "======================================================"
echo ""
echo "Next steps:"
echo "  1. Start the server:  cd $(pwd) && npm install && node index.js"
echo "  2. Set env vars in your shell or .env file (see .env.example)"
echo "  3. Visit https://$DOMAIN/notion-test to test Notion OAuth"
echo ""
echo "To stop the tunnel:  launchctl unload $PLIST_PATH"
echo "To view logs:        tail -f ~/.cloudflared/tunnel.log"
