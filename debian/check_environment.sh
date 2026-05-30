#!/bin/bash

if [ "$(id -u)" != "0" ]; then
    echo "错误: 此脚本需要 root 权限"
    exit 1
fi

if command -v sing-box &> /dev/null; then
    current_version=$(sing-box version | grep 'sing-box version' | awk '{print $3}')
    echo "sing-box 已安装，版本：$current_version"
else
    echo "sing-box 未安装"
fi

FORWARD_CONF="/etc/sysctl.d/99-sbshell-forward.conf"

ensure_ip_forwarding() {
    local ipv4_forward
    local ipv6_forward

    mkdir -p "$(dirname "$FORWARD_CONF")"
    cat > "$FORWARD_CONF" <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF

    ipv4_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)
    ipv6_forward=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo 1)

    if [ "$ipv4_forward" -eq 1 ] && [ "$ipv6_forward" -eq 1 ]; then
        echo "IP 转发已开启，持久化配置已确认"
        return
    fi

    echo "开启 IP 转发..."
    if sysctl -n net.ipv4.ip_forward >/dev/null 2>&1; then
        sysctl -w net.ipv4.ip_forward=1 >/dev/null
    fi
    if sysctl -n net.ipv6.conf.all.forwarding >/dev/null 2>&1; then
        sysctl -w net.ipv6.conf.all.forwarding=1 >/dev/null
    fi

    sysctl -p "$FORWARD_CONF" >/dev/null 2>&1 || true
    echo "IP 转发已成功开启"
}

ensure_ip_forwarding
