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

test_debian_forwarding_is_persistent_and_runtime() {
    local script="$REPO_ROOT/debian/check_environment.sh"

    assert_contains "$script" "/etc/sysctl.d/99-sbshell-forward.conf"
    assert_contains "$script" "net.ipv4.ip_forward=1"
    assert_contains "$script" "net.ipv6.conf.all.forwarding=1"
    assert_contains "$script" "sysctl -w net.ipv4.ip_forward=1"
    assert_contains "$script" "sysctl -w net.ipv6.conf.all.forwarding=1"
}

test_openwrt_forwarding_is_persistent_and_runtime() {
    local script="$REPO_ROOT/openwrt/check_environment.sh"

    assert_contains "$script" "/etc/sysctl.d/99-sbshell-forward.conf"
    assert_contains "$script" "net.ipv4.ip_forward=1"
    assert_contains "$script" "net.ipv6.conf.all.forwarding=1"
    assert_contains "$script" "sysctl -w net.ipv4.ip_forward=1"
    assert_contains "$script" "sysctl -w net.ipv6.conf.all.forwarding=1"
}

test_debian_server_initialization_runs_environment_check() {
    local script="$REPO_ROOT/debian/menu.sh"
    local server_body

    server_body="$(awk '/server_initialize\(\)/,/^}/' "$script")"
    printf '%s' "$server_body" | grep -Fq -- 'run_script "检查系统环境" "check_environment.sh" --quiet' \
        || fail "Expected server_initialize to run check_environment.sh"
}

test_debian_forwarding_is_persistent_and_runtime
test_openwrt_forwarding_is_persistent_and_runtime
test_debian_server_initialization_runs_environment_check

printf 'IP forwarding tests passed.\n'
