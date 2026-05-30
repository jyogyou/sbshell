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
    grep -Fq "$expected" "$file" || fail "Expected $file to contain: $expected"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    if grep -Fq "$unexpected" "$file"; then
        fail "Expected $file not to contain: $unexpected"
    fi
}

write_mock_bin() {
    local bin_dir="$1"
    local log_file="$2"

    cat > "$bin_dir/ip" <<'MOCK_IP'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    "addr show")
        printf '2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n'
        printf '    inet 192.0.2.10/24 brd 192.0.2.255 scope global ens3\n'
        ;;
    "route show default")
        printf 'default via 192.0.2.1 dev ens3 proto dhcp src 192.0.2.10 metric 100\n'
        ;;
    "-br link show")
        printf 'lo               UNKNOWN        00:00:00:00:00:00 <LOOPBACK>\n'
        printf 'ens3             UP             52:54:00:12:34:56 <BROADCAST,MULTICAST,UP,LOWER_UP>\n'
        ;;
    *)
        printf 'unexpected ip args: %s\n' "$*" >&2
        exit 1
        ;;
esac
MOCK_IP

    cat > "$bin_dir/systemctl" <<MOCK_SYSTEMCTL
#!/usr/bin/env bash
printf 'systemctl %s\n' "\$*" >> '$log_file'
MOCK_SYSTEMCTL

    cat > "$bin_dir/netplan" <<MOCK_NETPLAN
#!/usr/bin/env bash
printf 'netplan %s\n' "\$*" >> '$log_file'
MOCK_NETPLAN

    cat > "$bin_dir/sudo" <<'MOCK_SUDO'
#!/usr/bin/env bash
exec "$@"
MOCK_SUDO

    chmod +x "$bin_dir/ip" "$bin_dir/systemctl" "$bin_dir/netplan" "$bin_dir/sudo"
}

make_os_release() {
    local root="$1"
    local id="$2"
    local version="$3"
    mkdir -p "$root/etc"
    cat > "$root/etc/os-release" <<EOF_OS
ID=$id
VERSION_ID="$version"
EOF_OS
}

run_set_network_case() {
    local id="$1"
    local version="$2"
    local tmp_root
    local mock_bin
    local command_log

    tmp_root="$(mktemp -d)"
    mock_bin="$tmp_root/bin"
    command_log="$tmp_root/commands.log"
    mkdir -p "$mock_bin"
    : > "$command_log"

    make_os_release "$tmp_root" "$id" "$version"
    write_mock_bin "$mock_bin" "$command_log"

    PATH="$mock_bin:$PATH" \
    SBSHELL_ROOT="$tmp_root" \
    SBSHELL_OS_RELEASE="$tmp_root/etc/os-release" \
    bash "$REPO_ROOT/debian/set_network.sh" <<'EOF_INPUT' >/tmp/sbshell-set-network.out
203.0.113.10
203.0.113.1
1.1.1.1 8.8.8.8
y
EOF_INPUT

    printf '%s\n' "$tmp_root"
}

test_static_contracts() {
    assert_contains "$REPO_ROOT/debian/set_network.sh" "SBSHELL_ROOT"
    assert_contains "$REPO_ROOT/debian/set_network.sh" "netplan apply"
    assert_contains "$REPO_ROOT/debian/set_network.sh" "/etc/network/interfaces"
    assert_not_contains "$REPO_ROOT/debian/start_singbox.sh" "暂只支持debian"

    local bad_owner="qlj""syph"
    if git -C "$REPO_ROOT" grep -n "$bad_owner" -- '*.sh' 'README.md' ':!tests/*' >/tmp/sbshell-url-grep.out; then
        cat /tmp/sbshell-url-grep.out >&2
        fail "Tracked shell scripts and README should not link to the original author's repository"
    fi
}

test_ubuntu_netplan_generation() {
    local root
    root="$(run_set_network_case ubuntu 24.04)"

    local netplan_file="$root/etc/netplan/99-sbshell-static.yaml"
    [ -f "$netplan_file" ] || fail "Ubuntu 24.04 should generate $netplan_file"
    assert_contains "$netplan_file" "renderer: networkd"
    assert_contains "$netplan_file" "ens3:"
    assert_contains "$netplan_file" "addresses: [203.0.113.10/24]"
    assert_contains "$netplan_file" "via: 203.0.113.1"
    assert_contains "$netplan_file" "addresses: [1.1.1.1, 8.8.8.8]"
    assert_contains "$root/commands.log" "netplan apply"

    root="$(run_set_network_case ubuntu 26.04)"
    [ -f "$root/etc/netplan/99-sbshell-static.yaml" ] || fail "Ubuntu 26.04 should generate Netplan config"
    assert_contains "$root/commands.log" "netplan apply"
}

test_debian_ifupdown_is_preserved() {
    local root
    root="$(run_set_network_case debian 12)"

    local interfaces_file="$root/etc/network/interfaces"
    [ -f "$interfaces_file" ] || fail "Debian should still generate $interfaces_file"
    assert_contains "$interfaces_file" "iface ens3 inet static"
    assert_contains "$interfaces_file" "address 203.0.113.10"
    assert_contains "$interfaces_file" "gateway 203.0.113.1"
    assert_contains "$root/etc/resolv.conf" "nameserver 1.1.1.1"
    assert_contains "$root/commands.log" "systemctl restart networking"
}

test_static_contracts
test_ubuntu_netplan_generation
test_debian_ifupdown_is_preserved

printf 'Ubuntu support tests passed.\n'
