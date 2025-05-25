#!/bin/bash

# 安装依赖
apt update -y
apt install -y curl wget unzip openssl

# 生成 UUID
UUID=$(openssl rand -hex 16 | sed 's/................................/\1-\2-\3-\4-\5/')

# 下载 Xray Core
mkdir -p /usr/local/etc/xray
mkdir -p /usr/local/bin
cd /usr/local/bin
wget -O xray https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip Xray-linux-64.zip
chmod +x xray
rm -f Xray-linux-64.zip

# 生成 Xray 配置
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
            "flow": "xtls-rprx-vision",
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
          "path": "/$UUID"
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

# 写入 systemd 服务
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动 Xray
systemctl daemon-reexec
systemctl enable xray
systemctl restart xray

# 下载 cloudflared
wget -O /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x /usr/local/bin/cloudflared

# 启动 Argo 隧道
nohup cloudflared tunnel --url http://127.0.0.1:8080 > /root/argo.log 2>&1 &

# 等待几秒让 argo 启动
sleep 5

# 提取公网地址
ARGO_URL=$(grep -o 'https://[^ ]*trycloudflare.com' /root/argo.log | tail -n1)

# 显示 VLESS 配置信息
echo -e "\n==== 配置信息 ===="
echo "协议：VLESS"
echo "UUID：$UUID"
echo "路径：/$UUID"
echo "TLS：开启 (Cloudflare Argo)"
echo "WebSocket：开启"
echo "Argo 公网地址：$ARGO_URL"
echo -e "\n推荐客户端链接："
echo "vless://$UUID@$ARGO_URL:443?encryption=none&security=tls&type=ws&host=$(echo $ARGO_URL | cut -d/ -f3)&path=/$UUID#VLESS-ARGO"
