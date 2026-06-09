#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="/etc/sing-box/scripts"
MODE_FILE="/etc/sing-box/mode.conf"
NFT_SERVICE_FILE="/etc/systemd/system/nftables-singbox.service"
DROPIN_DIR="/etc/systemd/system/sing-box.service.d"
DROPIN_FILE="$DROPIN_DIR/sbshell-firewall.conf"

read_mode() {
    if [ ! -f "$MODE_FILE" ]; then
        echo -e "${RED}模式文件不存在: $MODE_FILE${NC}" >&2
        return 1
    fi

    grep -E '^MODE=' "$MODE_FILE" | head -n 1 | cut -d'=' -f2- | tr -d '\r'
}

apply_firewall() {
    local MODE
    MODE=$(read_mode) || return 1

    case "$MODE" in
        TProxy)
            echo "应用 TProxy 模式下的防火墙规则..."
            bash "$SCRIPT_DIR/configure_tproxy.sh"
            ;;
        TUN)
            echo "应用 TUN 模式下的防火墙规则..."
            bash "$SCRIPT_DIR/configure_tun.sh"
            ;;
        *)
            echo -e "${RED}无效的模式: ${MODE:-空}，跳过防火墙规则应用。${NC}" >&2
            return 1
            ;;
    esac
}

if [ "${1:-}" = "apply_firewall" ]; then
    apply_firewall
    exit $?
fi

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行自启动管理。${NC}" >&2
    exit 1
fi

enable_autostart() {
    echo -e "${GREEN}启用 sing-box 与防火墙规则联动自启动...${NC}"

    cat > "$NFT_SERVICE_FILE" <<EOF
[Unit]
Description=Apply nftables rules for Sing-Box
Wants=network-online.target
After=network-online.target
Before=sing-box.service

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_DIR/manage_autostart.sh apply_firewall

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p "$DROPIN_DIR"
    cat > "$DROPIN_FILE" <<EOF
[Unit]
Requires=nftables-singbox.service
After=nftables-singbox.service
EOF

    systemctl daemon-reload
    systemctl enable nftables-singbox.service sing-box.service
    echo -e "${GREEN}自启动已启用。下次开机将先应用防火墙规则，再启动 sing-box。${NC}"
    echo -e "${YELLOW}当前运行中的 sing-box 和防火墙服务未被启动、停止或重启。${NC}"
}

disable_autostart() {
    echo -e "${YELLOW}禁用 sing-box 与防火墙规则联动自启动...${NC}"

    systemctl disable nftables-singbox.service sing-box.service >/dev/null 2>&1 || true
    rm -f "$NFT_SERVICE_FILE"
    rm -f "$DROPIN_FILE"
    rmdir "$DROPIN_DIR" 2>/dev/null || true
    systemctl daemon-reload

    echo -e "${GREEN}自启动已禁用。当前运行中的 sing-box 和防火墙服务未被停止。${NC}"
}

echo -e "${GREEN}设置开机自启动...${NC}"
echo "请选择操作(1: 启用自启动, 2: 禁用自启动）"
read -rp "(1/2): " autostart_choice

case $autostart_choice in
    1)
        enable_autostart
        ;;
    2)
        disable_autostart
        ;;
    *)
        echo -e "${RED}无效的选择${NC}"
        ;;
esac
