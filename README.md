# luci-app-vnt2
OpenWrt LuCI plugin for VNT v2 (Virtual Network Tunnel)，用于在 OpenWrt 路由器上可视化配置和管理 VNT v2 虚拟网络隧道。

## 兼容性
- 适配 OpenWrt 版本：21.02 / 22.03 / SNAPSHOT
- 依赖 LuCI 版本：luci-base (>= git-22.183.35337)
- 依赖系统组件：curl、openssl-util、vnt2-core（需提前安装 VNT v2 核心运行库）

## 安装方式
### 方式1：源码编译（推荐，适配自有 OpenWrt 编译环境）
1. 将插件源码放入 OpenWrt 源码包的 `package/lean/` 目录（或自定义插件目录）；
2. 进入 OpenWrt 源码根目录，执行编译配置：`make menuconfig` → 选择 `LuCI → Applications → luci-app-vnt2`；
3. 编译插件（仅编译该插件）：`make package/luci-app-vnt2/compile V=s`；
4. 编译产物路径：`bin/packages/$(arch)/luci/luci-app-vnt2_2.0.0-1_all.ipk`（$(arch) 为你的设备架构，如 aarch64_cortex-a53）。

### 方式2：直接安装 IPK 包
1. 下载适配设备架构的 IPK 包（需确保与 OpenWrt 版本匹配）；
2. 上传 IPK 到路由器，执行安装：`opkg install luci-app-vnt2_2.0.0-1_all.ipk`；
3. 若安装提示依赖缺失，先补装依赖：`opkg install curl openssl-util`。

## 使用指南
### 基础配置
1. 登录 OpenWrt LuCI 后台 → 网络 → VNT2；
2. 填写核心参数：
   - 服务器地址：VNT v2 服务端的公网 IP/域名；
   - 端口：服务端监听的端口（默认一般为 10086，需与服务端一致）；
   - Token：隧道认证密钥（需与服务端配置的 Token 完全一致）；
3. 勾选「启用」，点击「保存&应用」，隧道将自动启动。

### 状态查看与排错
1. 查看隧道状态：登录路由器终端，执行 `vnt2 status`；
2. 查看运行日志：`logread | grep vnt2`；
3. 常见问题：
   - 隧道无法启动：检查服务器地址/端口是否可达（`ping 服务器IP` + `telnet 服务器IP 端口`）；
   - 认证失败：核对 Token 是否一致，服务端是否开启对应权限；
   - 界面无 VNT2 选项：检查 LuCI 版本是否兼容，插件是否安装成功（`opkg list-installed | grep vnt2`）。

## 卸载
```bash
opkg remove luci-app-vnt2
