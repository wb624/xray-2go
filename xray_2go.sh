#!/bin/bash

# 必要变量
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PORT=${PORT:-3633}
CFIP=${CFIP:-www.visa.com.tw}
CFPORT=${CFPORT:-443}
WORKDIR="/etc/xray"
XRAY_BIN="${WORKDIR}/xray"
ARGO_BIN="${WORKDIR}/argo"
CONFIG_FILE="${WORKDIR}/config.json"

# 安装依赖
apt update -y && apt install -y curl unzip

# 下载 Xray 和 cloudflared
mkdir -p ${WORKDIR}
ARCH=$(uname -m)
ARCH_ARG="64"
[ "$ARCH" = "aarch64" ] && ARCH_ARG="arm64-v8a"

curl -Lo ${WORKDIR}/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip
curl -Lo ${ARGO_BIN} https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}
chmod +x ${ARGO_BIN}
unzip -o ${WORKDIR}/xray.zip -d ${WORKDIR}
chmod +x ${XRAY_BIN}
rm -f ${WORKDIR}/xray.zip

# 写入 Xray 配置
cat > ${CONFIG_FILE} <<EOF
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
ExecStart=${XRAY_BIN} run -c ${CONFIG_FILE}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Argo Tunnel
After=network.target

[Service]
ExecStart=${ARGO_BIN} tunnel --url http://localhost:${PORT} --no-autoupdate --edge-ip-version auto --protocol http2
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable xray argo
systemctl start xray argo

# 等待 Argo 域名生成
echo -e "\n等待 Argo 域名生成中..."
for i in {1..10}; do
  sleep 2
  DOMAIN=$(grep -oP 'https://\K[^"]*trycloudflare\.com' ${WORKDIR}/argo.log 2>/dev/null)
  [ -n "$DOMAIN" ] && break
done

# 输出信息
echo -e "\nXray 已部署完成"
echo "UUID: $UUID"
if [ -n "$DOMAIN" ]; then
  echo -e "\n=== VLESS 节点链接 ==="
  echo "vless://${UUID}@${CFIP}:${CFPORT}?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless-argo#Argo-VLESS"
else
  echo -e "\nArgo 域名获取失败，请稍后查看 /etc/xray/argo.log"
fi
