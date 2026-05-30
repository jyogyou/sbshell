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

write_mock_bin() {
    local bin_dir="$1"
    local log_file="$2"

    cat > "$bin_dir/wget" <<MOCK_WGET
#!/usr/bin/env bash
printf 'wget %s\n' "\$*" >> '$log_file'
exit 1
MOCK_WGET

    cat > "$bin_dir/systemctl" <<MOCK_SYSTEMCTL
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >> '$log_file'
MOCK_SYSTEMCTL

    chmod +x "$bin_dir/wget" "$bin_dir/systemctl"
}

test_existing_server_config_is_not_overwritten() {
    local tmp_root
    local config_dir
    local mock_bin
    local command_log

    tmp_root="$(mktemp -d)"
    config_dir="$tmp_root/etc/sing-box"
    mock_bin="$tmp_root/bin"
    command_log="$tmp_root/commands.log"
    mkdir -p "$config_dir" "$mock_bin"
    printf '{"existing":true}\n' > "$config_dir/config.json"
    : > "$command_log"
    write_mock_bin "$mock_bin" "$command_log"

    PATH="$mock_bin:$PATH" \
    SBSHELL_CONFIG_DIR="$config_dir" \
    bash "$REPO_ROOT/debian/update_config.sh" >/tmp/sbshell-update-config.out

    grep -Fq '{"existing":true}' "$config_dir/config.json" || fail "Existing server config was changed"
    [ ! -s "$command_log" ] || fail "Existing config should skip wget/systemctl, got: $(cat "$command_log")"
}

test_generation_scripts_have_preserve_guard() {
    assert_contains "$REPO_ROOT/debian/update_config.sh" "SBSHELL_CONFIG_DIR"
    assert_contains "$REPO_ROOT/debian/update_config.sh" "配置文件已存在"
    assert_contains "$REPO_ROOT/debian/manual_input.sh" "CONFIG_FILE"
    assert_contains "$REPO_ROOT/debian/manual_input.sh" "配置文件已存在"
    assert_contains "$REPO_ROOT/openwrt/manual_input.sh" "CONFIG_FILE"
    assert_contains "$REPO_ROOT/openwrt/manual_input.sh" "配置文件已存在"
    assert_not_contains "$REPO_ROOT/debian/manual_input.sh" "-o /etc/sing-box/config.json"
    assert_not_contains "$REPO_ROOT/openwrt/manual_input.sh" "-o /etc/sing-box/config.json"
}

test_existing_server_config_is_not_overwritten
test_generation_scripts_have_preserve_guard

printf 'Config preserve tests passed.\n'
