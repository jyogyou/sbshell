#!/bin/bash

# 定义颜色
CYAN='\033[0;36m'
GREEN='\033[0;32m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 脚本下载目录
SCRIPT_DIR="/etc/sing-box/scripts"
MODE_FILE="/etc/sing-box/mode.conf"

read_mode() {
    if [ ! -f "$MODE_FILE" ]; then
        echo -e "${RED}模式文件不存在: $MODE_FILE，请先执行模式切换。${NC}" >&2
        return 1
    fi

    grep -E '^MODE=' "$MODE_FILE" | head -n 1 | cut -d'=' -f2- | tr -d '\r'
}

# 检查当前模式
check_mode() {
    if nft list chain inet sing-box prerouting_tproxy &>/dev/null || nft list chain inet sing-box output_tproxy &>/dev/null; then
        echo "TProxy 模式"
    else
        echo "TUN 模式"
    fi
}

# 应用防火墙规则
apply_firewall() {
    local MODE
    MODE="$(read_mode)" || return 1

    case "$MODE" in
        TProxy)
            echo -e "${CYAN}配置 TProxy 防火墙规则...${NC}"
            bash "$SCRIPT_DIR/configure_tproxy.sh"
            ;;
        TUN)
            echo -e "${CYAN}配置 TUN 防火墙规则...${NC}"
            bash "$SCRIPT_DIR/configure_tun.sh"
            ;;
        *)
            echo -e "${RED}未知代理模式: ${MODE:-空}，请重新执行模式切换。${NC}" >&2
            return 1
            ;;
    esac
}

# 启动 sing-box 服务
start_singbox() {
    echo -e "${CYAN}检测是否处于非代理环境...${NC}"
    STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://www.google.com")

    if [ "$STATUS_CODE" -eq 200 ]; then
        echo -e "${RED}当前网络处于代理环境, 启动 sing-box 需要直连, 请设置!${NC}"
        read -rp "是否执行网络设置脚本(Debian/Ubuntu/Armbian)?(y/n/skip): " network_choice
        if [[ "$network_choice" =~ ^[Yy]$ ]]; then
            bash "$SCRIPT_DIR/set_network.sh"
            STATUS_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://www.google.com")
            if [ "$STATUS_CODE" -eq 200 ]; then
                echo -e "${RED}网络配置更改后依然处于代理环境，请检查网络配置!${NC}"
                exit 1
            fi
        elif [[ "$network_choice" =~ ^[Ss]kip$ ]]; then
            echo -e "${CYAN}跳过网络检查，直接启动 sing-box。${NC}"
        else
            echo -e "${RED}请切换到非代理环境后再启动 sing-box。${NC}"
            exit 1
        fi
    else
        echo -e "${CYAN}当前网络环境非代理网络，可以启动 sing-box。${NC}"
    fi

    if ! sudo systemctl restart sing-box &>/dev/null; then
        echo -e "${RED}sing-box 启动失败，请检查日志${NC}"
        return 1
    fi

    if systemctl is-active --quiet sing-box; then
        if ! apply_firewall; then
            echo -e "${RED}防火墙规则应用失败，请检查 nftables、策略路由和模式配置。${NC}"
            return 1
        fi

        echo -e "${GREEN}sing-box 启动成功${NC}"
        mode=$(check_mode)
        echo -e "${MAGENTA}当前启动模式: ${mode}${NC}"
    else
        echo -e "${RED}sing-box 启动失败，请检查日志${NC}"
    fi
}

# 提示用户确认是否启动
read -rp "是否启动 sing-box?(y/n): " confirm_start
if [[ "$confirm_start" =~ ^[Yy]$ ]]; then
    start_singbox
else
    echo -e "${CYAN}已取消启动 sing-box。${NC}"
    exit 0
fi
