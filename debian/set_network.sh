#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

SBSHELL_ROOT="${SBSHELL_ROOT:-}"

root_path() {
    local path="$1"
    if [ -n "$SBSHELL_ROOT" ]; then
        printf '%s%s' "$SBSHELL_ROOT" "$path"
    else
        printf '%s' "$path"
    fi
}

OS_RELEASE_FILE="${SBSHELL_OS_RELEASE:-$(root_path /etc/os-release)}"

# 捕获 Ctrl+C 信号并处理
trap 'echo -e "\n${RED}操作已取消，返回到网络设置菜单。${NC}"; exit 1' SIGINT

read_os_value() {
    local key="$1"
    local value=""

    if [ -f "$OS_RELEASE_FILE" ]; then
        value=$(grep -E "^${key}=" "$OS_RELEASE_FILE" | head -n 1 | cut -d= -f2- || true)
    fi

    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

detect_network_backend() {
    local os_id os_like version_id
    os_id="$(read_os_value ID)"
    os_like="$(read_os_value ID_LIKE)"
    version_id="$(read_os_value VERSION_ID)"

    if [ "$os_id" = "ubuntu" ]; then
        case "$version_id" in
            24.04|26.04)
                echo -e "${GREEN}检测到 Ubuntu $version_id，将使用 Netplan 配置网络。${NC}" >&2
                ;;
            *)
                echo -e "${YELLOW}检测到 Ubuntu $version_id，将按 Netplan 配置网络；当前重点验证版本为 24.04/26.04。${NC}" >&2
                ;;
        esac
        printf 'netplan'
    elif [ "$os_id" = "debian" ] || [ "$os_id" = "armbian" ] || [[ "$os_like" == *"debian"* ]]; then
        printf 'ifupdown'
    else
        echo -e "${RED}不支持的系统：${os_id:-unknown}。此脚本仅支持 Debian/Ubuntu/Armbian。${NC}" >&2
        exit 1
    fi
}

run_privileged() {
    if [ -n "$SBSHELL_ROOT" ] || [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

ensure_parent_dir() {
    local target="$1"
    local parent
    parent="$(dirname "$target")"

    if [ -n "$SBSHELL_ROOT" ] || [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$parent"
    else
        sudo mkdir -p "$parent"
    fi
}

write_file() {
    local target="$1"
    local content="$2"

    ensure_parent_dir "$target"
    if [ -n "$SBSHELL_ROOT" ] || [ "$(id -u)" -eq 0 ]; then
        printf '%s\n' "$content" > "$target"
    else
        printf '%s\n' "$content" | sudo tee "$target" >/dev/null
    fi
}

normalize_cidr() {
    local ip_address="$1"
    if [[ "$ip_address" == */* ]]; then
        printf '%s' "$ip_address"
    else
        printf '%s/24' "$ip_address"
    fi
}

strip_cidr() {
    local ip_address="$1"
    printf '%s' "${ip_address%%/*}"
}

cidr_netmask() {
    local ip_address="$1"
    local prefix="${ip_address#*/}"

    if [[ "$ip_address" != */* ]]; then
        printf '255.255.255.0'
        return
    fi

    case "$prefix" in
        8) printf '255.0.0.0' ;;
        16) printf '255.255.0.0' ;;
        24) printf '255.255.255.0' ;;
        32) printf '255.255.255.255' ;;
        *)
            echo -e "${YELLOW}暂不支持自动换算 /$prefix，使用默认 255.255.255.0。${NC}" >&2
            printf '255.255.255.0'
            ;;
    esac
}

format_dns_list() {
    local result=""
    local dns

    for dns in $DNS_SERVERS; do
        if [ -z "$result" ]; then
            result="$dns"
        else
            result="$result, $dns"
        fi
    done

    printf '%s' "$result"
}

configure_netplan() {
    local netplan_file
    local cidr_address
    local dns_list
    local content

    netplan_file="$(root_path /etc/netplan/99-sbshell-static.yaml)"
    cidr_address="$(normalize_cidr "$IP_ADDRESS")"
    dns_list="$(format_dns_list)"

    content=$(cat <<EOL
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: false
      addresses: [$cidr_address]
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$dns_list]
EOL
)

    write_file "$netplan_file" "$content"
    run_privileged netplan apply
}

configure_ifupdown() {
    local interfaces_file
    local resolv_conf_file
    local address_without_cidr
    local netmask
    local interfaces_content
    local resolv_content=""
    local dns

    interfaces_file="$(root_path /etc/network/interfaces)"
    resolv_conf_file="$(root_path /etc/resolv.conf)"
    address_without_cidr="$(strip_cidr "$IP_ADDRESS")"
    netmask="$(cidr_netmask "$IP_ADDRESS")"

    interfaces_content=$(cat <<EOL
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug $INTERFACE
iface $INTERFACE inet static
    address $address_without_cidr
    netmask $netmask
    gateway $GATEWAY
EOL
)

    for dns in $DNS_SERVERS; do
        resolv_content="${resolv_content}nameserver $dns"$'\n'
    done

    write_file "$interfaces_file" "$interfaces_content"
    write_file "$resolv_conf_file" "${resolv_content%$'\n'}"
    run_privileged systemctl restart networking
}

validate_input() {
    if [ -z "$IP_ADDRESS" ] || [ -z "$GATEWAY" ] || [ -z "$DNS_SERVERS" ]; then
        echo -e "${RED}IP、网关和 DNS 均不能为空。${NC}"
        return 1
    fi

    return 0
}

NETWORK_BACKEND="$(detect_network_backend)"

# 获取当前系统的 IP 地址、网关和 DNS
CURRENT_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')
CURRENT_GATEWAY=$(ip route show default | awk '{print $3}')
CURRENT_DNS=$(grep 'nameserver' "$(root_path /etc/resolv.conf)" 2>/dev/null | awk '{print $2}')

echo -e "${YELLOW}当前 IP 地址: $CURRENT_IP${NC}"
echo -e "${YELLOW}当前网关地址: $CURRENT_GATEWAY${NC}"
echo -e "${YELLOW}当前 DNS 服务器: $CURRENT_DNS${NC}"

# 获取网卡名称
INTERFACE=$(ip -br link show | awk '$1 != "lo" {print $1; exit}' | cut -d@ -f1)
[ -z "$INTERFACE" ] && { echo -e "${RED}未找到网络接口，程序退出。${NC}"; exit 1; }

echo -e "${YELLOW}检测到的网络接口是: $INTERFACE${NC}"

while true; do
    # 提示用户输入静态 IP 地址、网关和 DNS
    read -rp "请输入静态 IP 地址 (Ubuntu 可直接输入 192.168.1.10 或 192.168.1.10/24): " IP_ADDRESS
    read -rp "请输入网关地址: " GATEWAY
    read -rp "请输入 DNS 服务器地址 (多个地址用空格分隔): " DNS_SERVERS

    validate_input || continue

    echo -e "${YELLOW}你输入的配置信息如下:${NC}"
    echo -e "IP 地址: $IP_ADDRESS"
    echo -e "网关地址: $GATEWAY"
    echo -e "DNS 服务器: $DNS_SERVERS"

    read -rp "是否确认上述配置信息? (y/n): " confirm_choice
    if [[ "$confirm_choice" =~ ^[Yy]$ ]]; then
        if [ "$NETWORK_BACKEND" = "netplan" ]; then
            configure_netplan
        else
            configure_ifupdown
        fi

        # 输出配置结果
        echo -e "${GREEN}静态 IP 地址和 DNS 配置完成！${NC}"
        break
    else
        echo -e "${RED}请重新输入配置信息。${NC}"
    fi
done
