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

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq -- "$unexpected" "$file"; then
        fail "Expected $file not to contain: $unexpected"
    fi
}

test_debian_start_surfaces_firewall_failures() {
    local script="$REPO_ROOT/debian/start_singbox.sh"

    assert_contains "$script" "read_mode()"
    assert_contains "$script" 'case "$MODE" in'
    assert_contains "$script" "配置 TProxy 防火墙规则"
    assert_contains "$script" "if ! apply_firewall; then"
    assert_contains "$script" "防火墙规则应用失败"
    assert_not_contains "$script" "grep -oP"
}

test_debian_tproxy_runs_with_privilege_and_applies_nft() {
    local script="$REPO_ROOT/debian/configure_tproxy.sh"

    assert_contains "$script" "#!/bin/bash"
    assert_contains "$script" 'exec sudo bash "$0" "$@"'
    assert_contains "$script" "MODE_FILE=\"/etc/sing-box/mode.conf\""
    assert_contains "$script" "cut -d'=' -f2-"
    assert_contains "$script" "set -euo pipefail"
    assert_contains "$script" "write_nft_rules()"
    assert_contains "$script" "validate_nft_rules()"
    assert_contains "$script" "install_policy_routing()"
    assert_contains "$script" "replace_nft_rules()"
    assert_contains "$script" "nft -c -f /etc/sing-box/nft/nftables.conf"
    assert_contains "$script" "nft -f /etc/sing-box/nft/nftables.conf"
    assert_contains "$script" "ip -f inet route replace local default"
    assert_not_contains "$script" "grep -oP"
}

test_debian_tun_runs_with_privilege() {
    local script="$REPO_ROOT/debian/configure_tun.sh"

    assert_contains "$script" 'exec sudo bash "$0" "$@"'
    assert_contains "$script" "MODE_FILE=\"/etc/sing-box/mode.conf\""
    assert_not_contains "$script" "grep -oP"
}

test_debian_start_surfaces_firewall_failures
test_debian_tproxy_runs_with_privilege_and_applies_nft
test_debian_tun_runs_with_privilege

printf 'TProxy firewall tests passed.\n'
