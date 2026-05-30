#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq -- "$expected" "$file" || fail "Expected $file to contain: $expected"
}

assert_file_exists() {
    local file="$1"
    [ -f "$file" ] || fail "Expected file to exist: $file"
}

test_debian_uninstall_script_contract() {
    local script="$REPO_ROOT/debian/uninstall.sh"

    assert_file_exists "$script"
    assert_contains "$script" "是否确认卸载"
    assert_contains "$script" "是否删除现有 config.json"
    assert_contains "$script" "systemctl disable"
    assert_contains "$script" "nft delete table inet sing-box"
    assert_contains "$script" "PROXY_ROUTE_TABLE=100"
    assert_contains "$script" "ip route flush table"
    assert_contains "$script" "/etc/sysctl.d/99-sbshell-forward.conf"
    assert_contains "$script" "/etc/netplan/99-sbshell-static.yaml"
    assert_contains "$script" "/usr/local/bin/sb"
    assert_contains "$script" "apt-get remove --auto-remove"
}

test_openwrt_uninstall_script_contract() {
    local script="$REPO_ROOT/openwrt/uninstall.sh"

    assert_file_exists "$script"
    assert_contains "$script" "是否确认卸载"
    assert_contains "$script" "是否删除现有 config.json"
    assert_contains "$script" "/etc/init.d/sing-box disable"
    assert_contains "$script" "nft delete table inet sing-box"
    assert_contains "$script" "PROXY_ROUTE_TABLE=100"
    assert_contains "$script" "ip route flush table"
    assert_contains "$script" "/etc/sysctl.d/99-sbshell-forward.conf"
    assert_contains "$script" "/usr/bin/sb"
    assert_contains "$script" "opkg remove"
}

test_menus_expose_uninstall() {
    assert_contains "$REPO_ROOT/debian/menu.sh" "uninstall.sh"
    assert_contains "$REPO_ROOT/debian/menu.sh" "卸载清理残留"
    assert_contains "$REPO_ROOT/debian/update_scripts.sh" "uninstall.sh"
    assert_contains "$REPO_ROOT/openwrt/menu.sh" "uninstall.sh"
    assert_contains "$REPO_ROOT/openwrt/menu.sh" "卸载清理残留"
    assert_contains "$REPO_ROOT/openwrt/update_scripts.sh" "uninstall.sh"
}

test_debian_uninstall_script_contract
test_openwrt_uninstall_script_contract
test_menus_expose_uninstall

printf 'Uninstall feature tests passed.\n'
