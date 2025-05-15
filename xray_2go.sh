#!/bin/bash

set -e

UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PORT=${PORT:-3633}
WORKDIR="/etc/xray"
XRAY_BIN="${WORKDIR}/xray"
ARGO_BIN="${WORKDIR}/argo"
CONFIG="${WORKDIR}/config.json"
DOMAIN="sd.wuoo.dpdns.org"
ARGO_TOKEN="eyJhIjoiMmI5NmIxMzY0MDI1ZDQ4NmNiYTIyOWViN2JkYmEzZmEiLCJ0IjoiNTQwYzQwZDktNmI1Yi00YTk2LWJjM2UtMzk2Y2I4YmE4ZWNhIiwicyI6IlptUm1aVEJqWkRjdFpERmtOeTAwTVRBMUxUaGlOekF0TnpSaU9UVTJabU14TlRJdyJ9"

mkdir -p ${WORKDIR}
apt update -y && apt install -y curl unzip jq net-tools || true

# 下载 Xray
ARCH=$(uname -m)
ARCH_ARG="64"; [ "$ARCH" = "aarch64" ] && ARCH_ARG="arm64-v8a"
curl -Lo ${WORKDIR}/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip
unzip -o ${WORKDIR}/xray.zip -d ${WORKDIR}
chmod +x ${WORKDIR}/xray
rm -f ${WORKDIR}/xray.zip

# 下载 cloudflared 并验证是否为 ELF 文件
if [ "$ARCH" = "aarch64" ]; then
  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
else
  CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
fi

curl -Lo ${ARGO_BIN} "$CF_URL"
chmod +x ${ARGO_BIN}

# 检查 cloudflared 是否是 ELF 二进制
if ! file ${ARGO_BIN} | grep -q "ELF"; then
  echo "错误：cloudflared 下载失败，获取到非二进制文件，可能是 HTML 页面"
  echo "请检查网络或 GitHub 下载失败，稍后重试"
  exit 1
fi

# 写入 Xray 配置
cat > ${CONFIG} <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}" }],
        "decryption": "none",
        "fallbacks": [{ "path": "/vless-argo", "dest": 3001 }]
      },
      "streamSettings": { "network": "tcp" }
    },
    {
      "port": 3001,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "${UUID}" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "/vless-argo" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 写入 systemd 服务
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=${XRAY_BIN} run -c ${CONFIG}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Cloudflare Argo (固定Token)
After=network.target

[Service]
ExecStart=${ARGO_BIN} tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_TOKEN}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable xray argo
systemctl restart xray argo

# 输出 VLESS 节点
echo -e "\n=== 部署完成 ==="
echo "UUID: ${UUID}"
echo ""
echo "=== VLESS 节点链接 ==="
echo "vless://${UUID}@www.visa.com.tw:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless-argo#Argo-Fixed"
