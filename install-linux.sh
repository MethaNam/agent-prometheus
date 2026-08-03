#!/bin/bash
# ============================================================
# Install Node Exporter (Linux)
# Supports: Ubuntu, Debian, CentOS, RHEL, Rocky Linux
#
# Usage:
#   curl -fsSL <RAW_URL>/install-linux.sh | sudo bash
#   sudo bash install-linux.sh [LISTEN_PORT]
# ============================================================

set -euo pipefail

NODE_EXPORTER_VERSION="1.8.2"
PORT="${1:-9100}"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "[✗] Unsupported architecture: $ARCH"; exit 1 ;;
esac

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[ "${EUID:-$(id -u)}" -ne 0 ] && err "Please run as root or with sudo"

log "Installing Node Exporter v${NODE_EXPORTER_VERSION} (${ARCH}) on port ${PORT}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz"
curl -fsSL "$URL" -o node_exporter.tar.gz
tar xf node_exporter.tar.gz
install -m 0755 "node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}/node_exporter" /usr/local/bin/node_exporter

id -u node_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter

cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \\
  --collector.systemd \\
  --collector.processes \\
  --web.listen-address=:${PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter

sleep 2
if curl -fsS "http://127.0.0.1:${PORT}/metrics" | grep -q "node_cpu"; then
  log "Node Exporter is running on port ${PORT}"
else
  err "Node Exporter did not respond on port ${PORT}"
fi

HOSTNAME_VALUE="$(hostname)"
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
IP="${IP:-127.0.0.1}"

echo
echo "======================================================"
echo " Add this scrape target to Prometheus"
echo "======================================================"
cat <<EOF
  - job_name: '${HOSTNAME_VALUE}'
    scrape_interval: 15s
    static_configs:
      - targets: ['${IP}:${PORT}']
        labels:
          hostname: '${HOSTNAME_VALUE}'
          os: 'linux'
EOF
echo "======================================================"
echo
warn "Open firewall / security group inbound TCP ${PORT} from Prometheus"
