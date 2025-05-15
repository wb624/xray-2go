#!/bin/bash

set -e

UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PORT=${PORT:-3633}
WORKDIR="/etc/xray"
XRAY_BIN="${WORKDIR}/xray"
ARGO_BIN="${WORKDIR}/argo"
CONFIG="${WORKDIR}/config.json"

# 下载依赖
apt update -y && apt install -y curl unzip jq

mkdir -p ${WORKDIR}

# 下载 xray 和 cloudflared
ARCH=$(uname -m)
ARCH_ARG="64"; [ "$ARCH" = "aarch64" ] && ARCH_ARG="arm64-v8a"
curl -Lo ${WORKDIR}/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip
curl -Lo ${ARGO_BIN} https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}
chmod +x ${ARGO_BIN}
unzip -o ${WORKDIR}/xray.zip -d ${WORKDIR} && chmod +x ${XRAY_BIN}
rm -f ${WORKDIR}/xray.zip

# 写入 xray 配置
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
Description=Xray
After=network.target

[Service]
ExecStart=${XRAY_BIN} run -c ${CONFIG}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Cloudflare Argo Tunnel (临时)
After=network.target

[Service]
ExecStart=${ARGO_BIN} tunnel --url http://localhost:${PORT} --no-autoupdate --edge-ip-version auto --protocol http2
StandardOutput=append:${WORKDIR}/argo.log
StandardError=append:${WORKDIR}/argo.log
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable xray argo
systemctl start xray argo

echo -e "\n等待 Argo 临时域名生成中..."
for i in {1..10}; do
    sleep 2
    DOMAIN=$(grep -oP 'https://\K[^ ]+\.trycloudflare\.com' ${WORKDIR}/argo.log | tail -n 1)
    [ -n "$DOMAIN" ] && break
done

echo -e "\n=== 部署完成 ==="
echo "UUID: ${UUID}"
if [ -n "$DOMAIN" ]; then
    echo ""
    echo "=== VLESS 节点链接 ==="
    echo "vless://${UUID}@www.visa.com.tw:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless-argo#临时Argo"
else
    echo "Argo 域名未获取成功，请稍后查看 /etc/xray/argo.log"
fi
