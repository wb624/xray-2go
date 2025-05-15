#!/bin/bash

set -e

WORKDIR="/etc/xray"
XRAY_BIN="${WORKDIR}/xray"
ARGO_BIN="${WORKDIR}/argo"
CONFIG="${WORKDIR}/config.json"
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PORT=${PORT:-3633}

# 准备环境
mkdir -p ${WORKDIR}
apt update -y && apt install -y curl unzip jq

# 下载 xray 和 cloudflared
ARCH=$(uname -m)
ARCH_ARG="64"; [ "$ARCH" = "aarch64" ] && ARCH_ARG="arm64-v8a"
curl -Lo ${WORKDIR}/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip
curl -Lo ${ARGO_BIN} https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}
unzip -o ${WORKDIR}/xray.zip -d ${WORKDIR} && chmod +x ${XRAY_BIN} ${ARGO_BIN}
rm -f ${WORKDIR}/xray.zip

# 询问用户选择方式
echo ""
echo "请选择 Argo 固定隧道配置方式："
echo "1. 使用 Token"
echo "2. 使用 JSON 文件"
read -rp "请输入选项 [1/2]: " method

if [ "$method" = "1" ]; then
    read -rp "请输入 Argo 固定隧道 Token: " ARGO_TOKEN
    read -rp "请输入你在 Cloudflare 上绑定的自定义域名（例如 argo.example.com）: " DOMAIN

    # 写入 systemd 服务
    cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Argo Tunnel (Token)
After=network.target

[Service]
ExecStart=${ARGO_BIN} tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_TOKEN}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

elif [ "$method" = "2" ]; then
    echo -e "\n请将 tunnel.json 上传至 ${WORKDIR}/tunnel.json 后按回车继续..."
    read -rsp "等待上传完成，按 Enter 继续..." _

    if [ ! -f "${WORKDIR}/tunnel.json" ]; then
        echo "未检测到 ${WORKDIR}/tunnel.json，退出。"
        exit 1
    fi

    read -rp "请输入你在 Cloudflare 上绑定的自定义域名（例如 argo.example.com）: " DOMAIN
    TUNNEL_ID=$(jq -r .TunnelID "${WORKDIR}/tunnel.json")

    # 写入 tunnel.yml
    cat > ${WORKDIR}/tunnel.yml <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${WORKDIR}/tunnel.json
protocol: http2

ingress:
  - hostname: ${DOMAIN}
    service: http://localhost:${PORT}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

    # 写入 systemd 服务
    cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Argo Tunnel (JSON)
After=network.target

[Service]
ExecStart=${ARGO_BIN} tunnel --config ${WORKDIR}/tunnel.yml run
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

else
    echo "无效选项，退出。"
    exit 1
fi

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

# 写入 xray systemd
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

# 启动服务
systemctl daemon-reload
systemctl enable xray argo
systemctl start xray argo

echo ""
echo "=== 安装完成 ==="
echo "UUID: ${UUID}"
echo ""
echo "VLESS 节点链接如下："
echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless-argo#Argo-VLESS"
