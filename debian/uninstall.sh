#!/bin/bash

set -u

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
SCRIPT_DIR="$CONFIG_DIR/scripts"
FORWARD_CONF="/etc/sysctl.d/99-sbshell-forward.conf"
NETPLAN_FILE="/etc/netplan/99-sbshell-static.yaml"
PROXY_ROUTE_TABLE=100
PROXY_FWMARK=666

confirm() {
    local prompt="$1"
    local answer
    read -rp "$prompt" answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

run_cmd() {
    "$@" >/dev/null 2>&1 || true
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}请使用 root 权限运行卸载清理。${NC}" >&2
        exit 1
    fi
}

stop_services() {
    echo -e "${CYAN}停止并禁用 sing-box 相关服务...${NC}"
    run_cmd systemctl stop sing-box.service
    run_cmd systemctl disable sing-box.service
    run_cmd systemctl stop nftables-singbox.service
    run_cmd systemctl disable nftables-singbox.service
    rm -f /etc/systemd/system/nftables-singbox.service
    run_cmd systemctl daemon-reload
}

clean_firewall_and_routes() {
    echo -e "${CYAN}清理 sing-box nftables、策略路由残留...${NC}"
    run_cmd nft delete table inet sing-box
    run_cmd ip rule del fwmark "$PROXY_FWMARK" lookup "$PROXY_ROUTE_TABLE"
    run_cmd ip -f inet rule del fwmark "$PROXY_FWMARK" lookup "$PROXY_ROUTE_TABLE"
    run_cmd ip route flush table "$PROXY_ROUTE_TABLE"
}

remove_shortcuts() {
    echo -e "${CYAN}删除 sb 快捷命令和 bashrc 别名...${NC}"
    rm -f /usr/local/bin/sb
    rm -f /usr/bin/sb

    if [ -f "$HOME/.bashrc" ]; then
        sed -i "\#alias sb=.*$SCRIPT_DIR/menu.sh#d" "$HOME/.bashrc"
        sed -i '\#alias sb=.*\/etc\/sing-box\/scripts\/menu.sh#d' "$HOME/.bashrc"
    fi
}

remove_config_dir() {
    local keep_config="$1"
    local backup_config=""

    if [ "$keep_config" = "yes" ] && [ -f "$CONFIG_FILE" ]; then
        backup_config="$(mktemp /tmp/sbshell-config.XXXXXX)"
        cp "$CONFIG_FILE" "$backup_config"
    fi

    rm -rf "$CONFIG_DIR"

    if [ -n "$backup_config" ] && [ -f "$backup_config" ]; then
        mkdir -p "$CONFIG_DIR"
        mv "$backup_config" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE" 2>/dev/null || true
        echo -e "${YELLOW}已保留原有 config.json: $CONFIG_FILE${NC}"
    fi
}

remove_optional_files() {
    echo -e "${CYAN}删除本脚本写入的转发持久化配置...${NC}"
    rm -f "$FORWARD_CONF"

    if [ -f "$NETPLAN_FILE" ]; then
        echo -e "${YELLOW}检测到本脚本生成的 Netplan 配置: $NETPLAN_FILE${NC}"
        if confirm "是否删除该 Netplan 静态网络配置? 默认不删除，避免断网 (y/N): "; then
            rm -f "$NETPLAN_FILE"
            if command -v netplan >/dev/null 2>&1; then
                run_cmd netplan apply
            fi
        fi
    fi
}

remove_packages() {
    if confirm "是否卸载 sing-box/sing-box-beta 软件包? 默认不卸载 (y/N): "; then
        echo -e "${CYAN}正在卸载 sing-box 软件包...${NC}"
        run_cmd apt-get remove --auto-remove -y sing-box sing-box-beta
    fi
}

main() {
    require_root

    echo -e "${RED}此操作会停止 sing-box，并清理 sbshell 脚本残留。${NC}"
    echo -e "${YELLOW}默认会保留现有 $CONFIG_FILE，除非你明确选择删除。${NC}"
    if ! confirm "是否确认卸载并清理残留? (y/N): "; then
        echo -e "${CYAN}已取消卸载清理。${NC}"
        exit 0
    fi

    local keep_config="yes"
    if [ -f "$CONFIG_FILE" ]; then
        if confirm "是否删除现有 config.json? 默认保留 (y/N): "; then
            keep_config="no"
        fi
    fi

    stop_services
    clean_firewall_and_routes
    remove_shortcuts
    remove_config_dir "$keep_config"
    remove_optional_files
    remove_packages

    echo -e "${GREEN}卸载清理完成。需要重新安装时，请重新执行一键脚本。${NC}"
}

main "$@"
