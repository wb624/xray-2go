#!/bin/bash

set -e

UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PORT=${PORT:-3633}
WORKDIR="/etc/xray"
XRAY_BIN="${WORKDIR}/xray"
ARGO_BIN="${WORKDIR}/argo"
CONFIG="${WORKDIR}/config.json"
LOG="${WORKDIR}/argo.log"

# 安装依赖
apt update -y && apt install -y curl unzip jq net-tools || true

mkdir -p ${WORKDIR}
touch ${LOG}
chmod 666 ${LOG}

# 下载 xray 和 cloudflared
ARCH=$(uname -m)
ARCH_ARG="64"; [ "$ARCH" = "aarch64" ] && ARCH_ARG="arm64-v8a"
curl -Lo ${WORKDIR}/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip
curl -Lo ${ARGO_BIN} https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}
chmod +x ${ARGO_BIN}
unzip -o ${WORKDIR}/xray.zip -d ${WORKDIR} && chmod +x ${XRAY_BIN}
rm -f ${WORKDIR}/xray.zip

# 生成 Xray 配置
cat > ${CONFIG} <<EOF
{
  "log": { "loglevel": "none" },
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

# 启动 Xray（后台）
nohup ${XRAY_BIN} run -c ${CONFIG} >/dev/null 2>&1 &

# 启动 cloudflared（后台）
nohup ${ARGO_BIN} tunnel --url http://localhost:${PORT} --no-autoupdate --edge-ip-version auto --protocol http2 > ${LOG} 2>&1 &

# 等待 Argo 域名生成
echo -e "\n等待 Argo 临时域名生成中..."
for i in {1..10}; do
  sleep 2
  DOMAIN=$(grep -oP 'https://\K[^ ]+\.trycloudflare\.com' ${LOG} | tail -n 1)
  [ -n "$DOMAIN" ] && break
done

echo ""
echo "=== 部署完成 ==="
echo "UUID: ${UUID}"
if [ -n "$DOMAIN" ]; then
  echo ""
  echo "=== VLESS 节点链接 ==="
  echo "vless://${UUID}@www.visa.com.tw:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless-argo#临时Argo"
else
  echo "Argo 域名获取失败，请稍后运行：grep trycloudflare ${LOG}"
fi
