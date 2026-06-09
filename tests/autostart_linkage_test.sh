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

test_systemd_firewall_apply_is_noninteractive() {
    local script="$REPO_ROOT/debian/manage_autostart.sh"

    assert_contains "$script" 'if [ "${1:-}" = "apply_firewall" ]; then'
    assert_contains "$script" "apply_firewall"
    assert_contains "$script" 'exit $?'
}

test_sing_box_service_uses_dropin_dependency() {
    local script="$REPO_ROOT/debian/manage_autostart.sh"

    assert_contains "$script" "/etc/systemd/system/sing-box.service.d"
    assert_contains "$script" "sbshell-firewall.conf"
    assert_contains "$script" "Requires=nftables-singbox.service"
    assert_contains "$script" "After=nftables-singbox.service"
    assert_contains "$script" "Before=sing-box.service"
    assert_not_contains "$script" "RemainAfterExit=yes"
    assert_not_contains "$script" "/usr/lib/systemd/system/sing-box.service"
}

test_systemd_firewall_apply_is_noninteractive
test_sing_box_service_uses_dropin_dependency

printf 'Autostart linkage tests passed.\n'
