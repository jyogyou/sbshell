#!/bin/bash

set -u

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    fi
    echo "错误: 配置 TUN 防火墙规则需要 root 权限。" >&2
    exit 1
fi

# 配置参数
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
MODE_FILE="/etc/sing-box/mode.conf"
INTERFACE=$(ip route show default | awk '/default/ {print $5}')

read_mode() {
    if [ ! -f "$MODE_FILE" ]; then
        echo "错误: 模式文件不存在: $MODE_FILE" >&2
        return 1
    fi

    grep -E '^MODE=' "$MODE_FILE" | head -n 1 | cut -d'=' -f2- | tr -d '\r'
}

# 读取当前模式
MODE=$(read_mode)

# 清理 TProxy 模式的防火墙规则
clearTProxyRules() {
    nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box
    while ip -f inet rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null; do :; done
    ip route flush table $PROXY_ROUTE_TABLE 2>/dev/null
    echo "清理 TProxy 模式的防火墙规则"
}

if [ "$MODE" = "TUN" ]; then
    echo "应用 TUN 模式下的防火墙规则..."

    # 清理 TProxy 模式的防火墙规则
    clearTProxyRules

    # 确保目录存在
    sudo mkdir -p /etc/sing-box/tun

    # 设置 TUN 模式的具体配置
    cat > /etc/sing-box/tun/nftables.conf <<EOF
# 清除现有的 nftables 规则并应用新的配置
flush ruleset
table inet filter {
    chain input { type filter hook input priority 0; policy accept; }
    chain forward { type filter hook forward priority 0; policy accept; }
    chain output { type filter hook output priority 0; policy accept; }
}
EOF

    # 应用防火墙规则
    nft -f /etc/sing-box/tun/nftables.conf

    # 持久化防火墙规则
    nft list ruleset > /etc/nftables.conf

    echo "TUN 模式的防火墙规则已应用。"
else
    echo "当前模式不是 TUN 模式，跳过防火墙规则配置。" >/dev/null 2>&1
fi
