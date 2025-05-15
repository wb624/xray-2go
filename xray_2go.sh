#!/bin/bash

# 设置变量
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
ARGO_PORT=8080
work_dir="/etc/xray"
config_file="${work_dir}/config.json"

# 安装xray和cloudflared
install_xray() {
    mkdir -p "${work_dir}"
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64) ARCH_ARG="64" ;;
        aarch64) ARCH_ARG="arm64-v8a" ;;
        *) echo "Unsupported architecture"; exit 1 ;;
    esac

    curl -Lo "${work_dir}/xray.zip" "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${ARCH_ARG}.zip"
    curl -Lo "${work_dir}/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}"
    unzip -o "${work_dir}/xray.zip" -d "${work_dir}" && chmod +x "${work_dir}/xray" "${work_dir}/argo"
    rm -f "${work_dir}/xray.zip"
}

# 生成配置文件
generate_config() {
    cat > "${config_file}" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": ${ARGO_PORT},
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
}

# 设置 systemd 启动服务
setup_services() {
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=${work_dir}/xray run -c ${config_file}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=Cloudflare Argo Tunnel
After=network.target

[Service]
ExecStart=${work_dir}/argo tunnel --url http://localhost:${ARGO_PORT} --no-autoupdate --edge-ip-version auto --protocol http2
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray argo
    systemctl start xray argo
}

main() {
    install_xray
    generate_config
    setup_services
    echo -e "\n已安装完成，UUID: ${UUID}"
    echo "如需Argo域名，请检查 /etc/xray/argo.log 获取 trycloudflare.com 地址"
}
main
