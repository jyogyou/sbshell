#!/bin/bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    fi
    echo "错误: 配置 TProxy 防火墙规则需要 root 权限。" >&2
    exit 1
fi

# 配置参数
TPROXY_PORT=7895  # 与 sing-box 中定义的一致
ROUTING_MARK=666  # 与 sing-box 中定义的一致
PROXY_FWMARK=1
PROXY_ROUTE_TABLE=100
MODE_FILE="/etc/sing-box/mode.conf"
INTERFACE=$(ip route show default | awk '/default/ {print $5; exit}')

# 保留 IP 地址集合
ReservedIP4='{ 127.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24, 198.51.100.0/24, 192.88.99.0/24, 192.168.0.0/16, 203.0.113.0/24, 224.0.0.0/4, 240.0.0.0/4, 255.255.255.255/32 }'
CustomBypassIP='{ 192.168.0.0/16, 10.0.0.0/8 }'  # 自定义绕过的 IP 地址集合

if [ -z "$INTERFACE" ]; then
    echo "错误: 未检测到默认网卡，无法配置 TProxy 路由。" >&2
    exit 1
fi

read_mode() {
    if [ ! -f "$MODE_FILE" ]; then
        echo "错误: 模式文件不存在: $MODE_FILE" >&2
        return 1
    fi

    grep -E '^MODE=' "$MODE_FILE" | head -n 1 | cut -d'=' -f2- | tr -d '\r'
}

# 读取当前模式
MODE=$(read_mode)

# 清理现有 sing-box 防火墙规则
clearSingboxRules() {
    nft list table inet sing-box >/dev/null 2>&1 && nft delete table inet sing-box
    echo "清理 sing-box 相关的防火墙规则"
}

install_policy_routing() {
    ip -f inet route replace local default dev "${INTERFACE}" table $PROXY_ROUTE_TABLE
    ip -f inet rule add fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
}

dedupe_policy_rules() {
    while ip -f inet rule del fwmark $PROXY_FWMARK lookup $PROXY_ROUTE_TABLE 2>/dev/null; do :; done
}

write_nft_rules() {
    mkdir -p /etc/sing-box/nft
    cat > /etc/sing-box/nft/nftables.conf <<EOF
table inet sing-box {
    set RESERVED_IPSET {
        type ipv4_addr
        flags interval
        auto-merge
        elements = $ReservedIP4
    }

    chain prerouting_tproxy {
        type filter hook prerouting priority mangle; policy accept;

        # DNS 请求重定向到本地 TProxy 端口
        meta l4proto { tcp, udp } th dport 53 tproxy to :$TPROXY_PORT accept

        # 自定义绕过地址
        ip daddr $CustomBypassIP accept

        # 拒绝访问本地 TProxy 端口
        fib daddr type local meta l4proto { tcp, udp } th dport $TPROXY_PORT reject with icmpx type host-unreachable

        # 本地地址绕过
        fib daddr type local accept

        # 保留地址绕过
        ip daddr @RESERVED_IPSET accept

        # 优化已建立的 TCP 连接
        meta l4proto tcp socket transparent 1 meta mark set $PROXY_FWMARK accept

        # 重定向剩余流量到 TProxy 端口并设置标记
        meta l4proto { tcp, udp } tproxy to :$TPROXY_PORT meta mark set $PROXY_FWMARK
    }

    chain output_tproxy {
        type route hook output priority mangle; policy accept;

        # 放行本地回环接口流量
        meta oifname "lo" accept

        # 本地 sing-box 发出的流量绕过
        meta mark $ROUTING_MARK accept

        # DNS 请求标记
        meta l4proto { tcp, udp } th dport 53 meta mark set $PROXY_FWMARK

        # 绕过 NBNS 流量
        udp dport { netbios-ns, netbios-dgm, netbios-ssn } accept

        # 自定义绕过地址
        ip daddr $CustomBypassIP accept

        # 本地地址绕过
        fib daddr type local accept

        # 保留地址绕过
        ip daddr @RESERVED_IPSET accept

        # 标记并重定向剩余流量
        meta l4proto { tcp, udp } meta mark set $PROXY_FWMARK
    }
}
EOF
}

validate_nft_rules() {
    nft -c -f /etc/sing-box/nft/nftables.conf
}

replace_nft_rules() {
    clearSingboxRules
    nft -f /etc/sing-box/nft/nftables.conf
    nft list ruleset > /etc/nftables.conf
}

# 仅在 TProxy 模式下应用防火墙规则
if [ "$MODE" = "TProxy" ]; then
    echo "应用 TProxy 模式下的防火墙规则..."

    # 先生成并校验新规则，避免新规则异常时删除正在工作的旧 nft 表。
    write_nft_rules
    validate_nft_rules

    # 路由设置成功后再替换 nft 表。
    dedupe_policy_rules
    install_policy_routing
    replace_nft_rules

    echo "TProxy 模式的防火墙规则已应用。"
else
    echo "当前模式为 TUN 模式，不需要应用防火墙规则。" >/dev/null 2>&1
fi
