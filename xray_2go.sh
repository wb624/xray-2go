#!/bin/bash

# 生成随机 UUID
UUID=$(cat /proc/sys/kernel/random/uuid)

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

# 重启 Xray 服务
systemctl restart xray

# 显示结果
echo ""
echo "===== Xray VLESS + WS + Argo Tunnel 配置完成 ====="
echo "UUID: $UUID"
echo "地址: closes-league-on-nepal.trycloudflare.com"
echo "端口: 443"
echo "协议: vless"
echo "传输: websocket (ws)"
echo "TLS: 开启"
echo "路径: /"
echo "host/sni: closes-league-on-nepal.trycloudflare.com"
echo "=============================================="
