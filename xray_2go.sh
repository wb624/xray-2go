#!/bin/bash

uuid=$(cat /proc/sys/kernel/random/uuid)
config_dir="/etc/xray/config.json"
ARGO_FILE="/etc/systemd/system/argo.service"

install_dependencies() {
  apt update -y
  apt install -y curl wget unzip socat cron xz-utils jq
}

install_xray() {
  mkdir -p /etc/xray
  bash -c "$(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

  cat > "${config_dir}" << EOF
{
  "log": { "loglevel": "none" },
  "inbounds": [
    {
      "port": 3002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$uuid", "level": 0 }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vless" }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

  cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/xray run -c ${config_dir}
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl enable xray
  systemctl restart xray
}

install_argo() {
  mkdir -p /etc/xray
  wget -O /etc/xray/argo https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x /etc/xray/argo

  cat > $ARGO_FILE << EOF
[Unit]
Description=Cloudflare Argo Tunnel
After=network.target

[Service]
ExecStart=/etc/xray/argo tunnel --url http://localhost:3002 --no-autoupdate --edge-ip-version auto --protocol http2
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl enable argo
  systemctl restart argo
}

show_info() {
  sleep 3
  echo "====== 配置信息 ======"
  echo "UUID: $uuid"
  echo "WebSocket 路径: /vless"
  echo "端口: 443 (由 Argo 转发)"
  echo "协议: vless + ws + tls"
  echo
  echo "Argo 地址稍后请通过以下命令查看（稍等几秒启动 Argo）："
  echo "journalctl -u argo -n 20 --no-pager | grep 'https://'"
}

install_dependencies
install_xray
install_argo
show_info
