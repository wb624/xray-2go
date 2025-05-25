#!/bin/bash
set -e

UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PORT=3633
WORKDIR="/etc/xray"
XRAY_BIN="${WORKDIR}/xray"
ARGO_BIN="${WORKDIR}/argo"
CONFIG="${WORKDIR}/config.json"
DOMAIN="sd.wuoo.dpdns.org"
ARGO_TOKEN="eyJhIjoiMmI5NmIxMzY0MDI1ZDQ4NmNiYTIyOWViN2JkYmEzZmEiLCJ0IjoiNTQwYzQwZDktNmI1Yi00YTk2LWJjM2UtMzk2Y2I4YmE4ZWNhIiwicyI6IlptUm1aVEJqWkRjdFpERmtOeTAwTVRBMUxUaGlOekF0TnpSaU9UVTJabU14TlRJdyJ9"

mkdir -p ${WORKDIR}
for pkg in curl unzip jq; do
    command -v $pkg >/dev/null 2>&1 || apt install -y $pkg
done

# 下载 Xray
ARCH=$(uname -m)
ARCH_ARG="64"; [ "$ARCH" = "aarch64" ] && ARCH_ARG="arm64-v8a"
curl -Lo ${WORKDIR}/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip
unzip -o ${WORKDIR}/xray.zip -d ${WORKDIR}
chmod +x ${XRAY_BIN}
rm -f ${WORKDIR}/xray.zip

# 下载 cloudflared
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH/amd64/amd64}"
CF_URL="${CF_URL/arm64/aarch64}"
curl -Lo ${ARGO_BIN} "$CF_URL"
chmod +x ${ARGO_BIN}
file ${ARGO_BIN} | grep -q ELF || { echo "cloudflared 下载失败"; exit 1; }

# 写入配置
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
        "fallbacks": [
          { "path": "/vless", "dest": 3001 },
          { "path": "/vmess", "dest": 3002 }
        ]
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
        "wsSettings": { "path": "/vless" }
      }
    },
    {
      "port": 3002,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "${UUID}" }]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" }
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
Description=Cloudflare Argo Tunnel
After=network.target

[Service]
ExecStart=${ARGO_BIN} tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_TOKEN}
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray argo
systemctl restart xray argo

# 输出结果
echo -e "\n=== 部署完成 ==="
echo "UUID: ${UUID}"
echo ""
echo "=== VLESS + Argo 节点 ==="
echo "vless://${UUID}@www.visa.com.tw:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless#VLESS-Argo"
echo ""
echo "=== VMESS + Argo 节点 ==="
echo "vmess://"$(echo -n "{
  \"v\": \"2\",
  \"ps\": \"VMESS-Argo\",
  \"add\": \"www.visa.com.tw\",
  \"port\": \"443\",
  \"id\": \"${UUID}\",
  \"aid\": \"0\",
  \"net\": \"ws\",
  \"type\": \"none\",
  \"host\": \"${DOMAIN}\",
  \"path\": \"/vmess\",
  \"tls\": \"tls\",
  \"sni\": \"${DOMAIN}\"
}" | base64 -w 0)
echo ""
echo "你可以使用以下命令查看日志："
echo "journalctl -u xray -e"
echo "journalctl -u argo -e"
