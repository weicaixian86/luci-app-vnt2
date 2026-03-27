
# luci-app-vnt2

VNT2 OpenWrt Luci 插件

## 简介

luci-app-vnt2 是 VNT2 的 OpenWrt Luci 界面插件，用于在 OpenWrt 路由器上方便地配置和管理 VNT2 虚拟网络。

VNT2 是一个简单、高效、能快速组建虚拟局域网的工具，支持多种协议连接，包括 quic、tcp、wss 等，并提供加密、压缩、FEC 等功能。

## 功能特性

- 支持 quic/tcp/wss/dynamic 协议连接服务器
- 支持 TLS 加密和证书验证
- 支持 QUIC 优化传输和 FEC 前向纠错
- 支持端口映射和点对网功能
- 支持多服务器连接，实现容灾和负载均衡
- 支持压缩和加密
- Web 界面管理，操作简单

## 安装方法

### 1. 通过 Releases 安装

1. 从 [Releases](https://github.com/yourusername/luci-app-vnt2/releases) 页面下载对应架构的 ipk 文件
2. 在 OpenWrt 的 "系统" -> "软件包" 页面上传并安装 ipk 文件
3. 安装完成后，在 "网络" -> "VNT2" 中配置和使用

### 2. 通过源码编译

1. 克隆本仓库到 OpenWrt SDK 的 package/feeds/luci 目录
2. 更新 feeds: `./scripts/feeds update -a`
3. 安装 feeds: `./scripts/feeds install -a`
4. 编译: `make package/feeds/luci/luci-app-vnt2/compile V=s`

## 使用说明

### 基本配置

1. 在 "网络" -> "VNT2" 中打开 VNT2 设置页面
2. 在 "基本设置" 标签页中配置以下参数：
   - 启用 VNT2
   - 服务器地址（支持多个服务器，用逗号分隔）
   - 网络编号（必填）
   - 设备 ID 和设备名称（可选）

### 高级配置

在 "高级设置" 标签页中可以配置：
- vnt2-cli 程序路径
- 虚拟网卡名称
- MTU 大小
- 控制端口和隧道端口
- P2P 打洞、QUIC 优化、压缩、FEC 等功能开关

### 网络配置

在 "网络设置" 标签页中可以配置：
- 入栈监听网段
- 出栈允许网段
- 端口映射规则

### 安全配置

在 "安全设置" 标签页中可以配置：
- 加密密码
- 证书验证模式（跳过验证/系统证书/证书指纹）

### 连接信息

在 "连接信息" 标签页中可以查看：
- 本机设备信息
- 客户端 IP 列表
- 客户端信息列表
- 路由转发信息

### 日志查看

在 "客户端日志" 页面可以查看和管理 VNT2 的运行日志。

## 上传程序

如果需要更新 vnt2_cli 程序，可以在 "上传程序" 标签页中上传新的二进制文件或压缩包。

## 注意事项

1. 确保 OpenWrt 系统已安装 kmod-tun 模块
2. 如果使用端口映射功能，请确保防火墙已放行相关端口
3. 建议使用 QUIC 协议以获得更好的性能和稳定性
4. 如果网络环境较差，可以启用 FEC 前向纠错提升稳定性

## 相关链接

- VNT 官网: http://rustvnt.com/
- VNT 项目地址: https://github.com/vnt-dev/vnt
- OpenWrt 官网: https://openwrt.org/

## 许可证

本项目遵循 Apache License 2.0 许可证。
