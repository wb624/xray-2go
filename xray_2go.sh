#!/bin/bash

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 权限运行本脚本"
  exit 1
fi

# 安装必要组件
apt update -y
apt install -y curl wget unzip sudo

# 生成 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)

# 安装 Xray Core
XRAY_DIR="/usr/local/bin"
XRAY_ZIP_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
mkdir -p /usr/local/etc/xray
cd /tmp
wget -O xray.zip "$XRAY_ZIP_URL"
unzip xray.zip -d xray
install -m 755 xray/xray "$XRAY_DIR/xray"
install -m 755 xray/geosite.dat /usr/local/share/xray/
install -m 755 xray/geoip.dat /usr/local/share/xray/
rm -rf /tmp/xray*

# 写入 Xray 配置文件
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 8080,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0,
            "email": "user@localhost"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 创建 Xray systemd 服务
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=$XRAY_DIR/xray -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

# 启动并启用 Xray
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 安装 Cloudflared
CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
wget -O $CLOUDFLARED_BIN https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x $CLOUDFLARED_BIN

# 启动 Cloudflared Argo Tunnel
ARGO_DOMAIN=$($CLOUDFLARED_BIN tunnel --url http://127.0.0.1:8080 --loglevel info | grep -o 'https://.*trycloudflare.com' | head -n 1)

# 输出配置信息
echo -e "\n===== 配置完成 ====="
echo "VLESS 节点信息如下："
echo "地址：${ARGO_DOMAIN/https:\/\/}"
echo "端口：443"
echo "UUID：$UUID"
echo "协议：vless"
echo "加密：none"
echo "传输协议：ws"
echo "路径：/"
echo "TLS：开启"
echo -e "====================\n"
