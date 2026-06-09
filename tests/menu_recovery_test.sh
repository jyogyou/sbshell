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

test_menu_recovers_existing_install_without_initialized_marker() {
    local script="$REPO_ROOT/debian/menu.sh"

    assert_contains "$script" "recover_existing_install()"
    assert_contains "$script" "detect_existing_role()"
    assert_contains "$script" 'touch "$INITIALIZED_FILE"'
    assert_contains "$script" "检测到已有安装"
    assert_contains "$script" "if recover_existing_install; then"
}

test_skip_download_marks_initialized_for_next_sb_run() {
    local script="$REPO_ROOT/debian/menu.sh"

    assert_contains "$script" "跳过初始化，仅下载脚本"
    assert_contains "$script" 'touch "$INITIALIZED_FILE"'
}

test_menu_recovers_existing_install_without_initialized_marker
test_skip_download_marks_initialized_for_next_sb_run

printf 'Menu recovery tests passed.\n'
