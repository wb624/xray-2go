#!/bin/bash

set -e

# 设置伪装域名（可修改）
FAKE_DOMAIN=example.com

# 设置 UUID 和路径
UUID=$(uuidgen)
WSPATH="/$(openssl rand -hex 4)"

# 创建必要目录
mkdir -p /etc/xray /usr/local/bin /root/.config/cloudflared

# 下载 Xray-core
curl -Lo /usr/local/bin/xray https://github.com/XTLS/Xray-core/releases/latest/download/xray-linux-64.zip
unzip -od /usr/local/bin /usr/local/bin/xray
chmod +x /usr/local/bin/xray

# 创建 Xray 配置文件
cat > /etc/xray/config.json <<EOF
{
  "inbounds": [{
    "port": 8080,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID","flow":"xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "$WSPATH" }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

# 创建 Xray systemd 服务
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动 Xray
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

# 安装 cloudflared
curl -Lo /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared

# 创建 Argo 启动脚本
cat > /root/argo.sh <<EOF
#!/bin/bash
nohup cloudflared tunnel --url http://localhost:8080 > /root/.argo.log 2>&1 &
EOF
chmod +x /root/argo.sh
bash /root/argo.sh

# 等待 Argo 启动并抓取公网地址
echo "等待 Argo 隧道建立..."
sleep 10
ARGO_URL=$(grep -o 'https://[^ ]*trycloudflare.com' /root/.argo.log | head -n1)

# 输出配置信息
clear
echo "====== VLESS + WS + TLS (Argo) 配置完成 ======"
echo "地址：$ARGO_URL"
echo "UUID：$UUID"
echo "路径：$WSPATH"
echo "加密：none"
echo "传输协议：ws"
echo "TLS：开启（Argo 提供）"
echo
echo "VLESS分享链接："
echo "vless://$UUID@$ARGO_URL:443?encryption=none&security=tls&type=ws&host=$FAKE_DOMAIN&path=$WSPATH#Argo-VLESS"
