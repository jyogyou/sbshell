# Sbshell

请遵守所在地法律法规，自行承担使用风险。

Sbshell 是一款针对官方 sing-box 的辅助运行脚本，旨在让官方 sing-box 更方便安装、配置和维护。

- **系统支持**：支持 Debian、Ubuntu、Armbian 以及 OpenWrt；Ubuntu 重点适配 24.04 和 26.04。
- **客户端运行**：客户端保持 sing-box 以官方裸核形式运行，追求精简与性能。
- **服务端运行**：支持服务端配置搭建，具体用法请结合 sing-box 官方文档。
- **双模支持**：兼容 TUN 和 TProxy 模式，可一键切换。
- **版本管理**：支持切换稳定版与测试版内核，并检测更新。
- **灵活配置**：支持手动输入后端地址、订阅链接、配置文件链接，并可设置默认值。
- **订阅管理**：支持手动更新和定时自动更新。
- **启动控制**：支持手动启动、停止和开机自启管理。
- **网络配置**：支持快速修改系统 IP、网关和 DNS。Ubuntu 24.04/26.04 使用 Netplan，Debian/Armbian 保留 ifupdown 配置方式。
- **便捷命令**：集成常用命令，减少手动查找。
- **在线更新**：脚本更新地址已指向当前仓库。
- **面板更新**：支持 clash 系面板在线更新/切换。

## 设备支持

目前支持：

- Debian
- Ubuntu 24.04 / 26.04
- Armbian
- OpenWrt

防火墙仅支持 nftables，不支持 iptables。

## 一键脚本

请先确保系统已安装 `curl` 和 `bash`。

```bash
bash <(curl -sL https://ghfast.top/https://raw.githubusercontent.com/jyogyou/sbshell/refs/heads/main/sbshall.sh)
```

初始化完成后，输入 `sb` 进入菜单。

非 OpenWrt 用户如果仍在使用 2.1.2 之前版本，并计划升级到 1.12.x 内核，建议卸载后重新安装。

## Ubuntu 24.04/26.04 说明

Ubuntu 24.04 和 26.04 的网络设置使用 Netplan：

- 静态 IP 配置写入 `/etc/netplan/99-sbshell-static.yaml`
- DNS 写入 Netplan `nameservers.addresses`
- 配置确认后执行 `netplan apply`

Debian/Armbian 仍使用 `/etc/network/interfaces` 和 `/etc/resolv.conf`，并重启 `networking` 服务。

## 适配配置文件

### 发行版 1.12

fakeiptrpoxy:

```text
https://raw.githubusercontent.com/jyogyou/sbshell/refs/heads/main/config_template/config_fakeiptrpoxy12.json
```

fakeiptun:

```text
https://raw.githubusercontent.com/jyogyou/sbshell/refs/heads/main/config_template/config_fakeiptun12.json
```

tproxy:

```text
https://raw.githubusercontent.com/jyogyou/sbshell/refs/heads/main/config_template/config_trpoxy12.json
```

### 发行版 1.11

tproxy:

```text
https://gh-proxy.com/https://raw.githubusercontent.com/jyogyou/sbshell/refs/heads/main/config_template/config_tproxy.json
```

tun:

```text
https://gh-proxy.com/https://raw.githubusercontent.com/jyogyou/sbshell/refs/heads/main/config_template/config_tun.json
```

## 注意事项

- 网络优化功能不熟悉时不建议使用，可能影响部分网络场景。
- 在线更新和初始化链式脚本均使用当前仓库 `jyogyou/sbshell`。
