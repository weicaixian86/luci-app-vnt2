# luci-app-vnt2

<p align="center">
  <img alt="OpenWrt" src="https://img.shields.io/badge/OpenWrt-24.10-blue?logo=openwrt">
  <img alt="LuCI" src="https://img.shields.io/badge/LuCI-VNT2-32c955">
  <img alt="Architecture" src="https://img.shields.io/badge/SDK-x86__64-orange">
  <img alt="Release" src="https://img.shields.io/badge/Release-Actions-success?logo=github">
</p>

`luci-app-vnt2` 是基于 **VNT 2.x** 客户端能力开发的 OpenWrt LuCI 插件，用于在 OpenWrt 24.10 上通过 Web 界面管理 `vnt2_cli`、`vnt2_ctrl` 和 `vnt2_web`。

> 注意：  
> `vnt-2` 是 **VNT V2** 版本源码，和 `vnt` 的 **V1** 版本不兼容，也没有直接关系。  
> 本项目对应的是 **VNT2**，不是 VNT1。

---

## 项目说明

本仓库内相关目录说明：

- `vnt-2/`  
  VNT2 上游源码，用于确认 V2 功能、参数和行为。
- `luci-app-vnt-main/`  
  VNT1 的 LuCI 插件源码，仅作为界面风格与交互参考。
- `luci-app-vnt2/`  
  当前的 VNT2 LuCI 插件工程。
- `luci-app-vnt2/.github/workflows/build.yml`  
  GitHub Actions 在线编译工作流，用于手动编译 OpenWrt 24.10 x86_64 的 ipk 安装包并自动发布 Release。

---

## 功能特性

当前 `luci-app-vnt2` 已围绕 VNT2 提供以下能力：

### 1. LuCI 图形化管理
- 在 OpenWrt 后台提供 VNT2 管理菜单
- 参考 V1 插件界面风格重新适配 V2
- 支持基础配置、状态查看、日志查看

### 2. vnt2_cli 管理
- 支持启停 `vnt2_cli`
- 支持通过 UCI 配置生成 TOML 配置文件
- 支持以下常见参数管理：
  - 服务器地址
  - 网络编号
  - 设备名称 / 设备 ID
  - IP
  - TUN 名称
  - 控制端口
  - Tunnel 端口
  - 密码
  - 绑定设备
  - 无 TUN 模式
  - 禁用打洞
  - NAT 相关选项
  - 压缩 / FEC / RTX
  - 输入 / 输出规则
  - 端口映射
  - STUN 服务器配置

### 3. vnt2_ctrl 集成
- 获取连接状态
- 获取本机信息
- 获取路由信息
- 获取客户端信息
- 获取命令行信息

### 4. vnt2_web 集成
- 支持启停 `vnt2_web`
- 支持设置监听地址和端口
- 支持页面按钮直接打开原生 `vnt2_web` 管理界面
- 支持按配置自动放行 Web 访问端口

### 5. 状态与日志
- 轮询显示 `vnt2_cli` / `vnt2_web` 运行状态
- 显示 PID、运行时长、CPU、内存占用
- 显示当前版本与 GitHub 最新版本
- 客户端日志查看
- Web 日志查看

### 6. OpenWrt 联动
- 自动处理 `network` / `firewall` 相关配置
- 支持 TUN 模式与无 TUN 模式切换
- 支持 init.d / procd 管理服务

---

## 适用环境

- OpenWrt `24.10`
- LuCI（传统 Lua CBI 体系）
- 目标工作流架构：`x86_64`

> 当前 GitHub Actions 工作流默认构建 `OpenWrt 24.10 x86_64` 的 `ipk` 包。

---

## 依赖说明

插件 Makefile 当前依赖：

- `luci-compat`
- `kmod-tun`
- `libopenssl`
- `libustream-openssl`

如果你使用 `TUN` 模式，请确保系统已安装：

```sh
opkg update
opkg install kmod-tun
```

---

## 安装方式

### 方式一：通过 GitHub Releases 安装 ipk

在你自己的 GitHub 仓库中运行 Actions 编译后，可在 Releases 中下载生成的 `ipk` 文件，然后在 OpenWrt 上安装：

```sh
opkg install luci-app-vnt2_*.ipk
```

如果你的 OpenWrt 固件使用的是 `apk` 包管理器，则请按系统实际方式安装。

---

## 在 OpenWrt 源码中编译

将本项目放到 OpenWrt/SDK 的 `package` 目录下，例如：

```sh
git clone <your-repo-url> package/luci-app-vnt2
```

然后执行：

```sh
make menuconfig
```

进入：

```text
LuCI  --->
  Applications  --->
    <*> luci-app-vnt2
```

最后编译：

```sh
make package/luci-app-vnt2/compile V=s
```

---

## GitHub Actions 在线编译

仓库已提供工作流文件：

```text
luci-app-vnt2/.github/workflows/build.yml
```

### 工作流特性
- 手动触发
- 使用 OpenWrt `24.10.0`
- 使用 `x86/64` SDK
- 自动编译 `luci-app-vnt2` 的 ipk 包
- 自动上传 Actions Artifact
- 自动发布 GitHub Releases
- Release 内容仅保留：
  - ipk 安装包
  - 编译时间

### 使用方法

1. 将整个 `luci-app-vnt2` 目录上传到你的 GitHub 仓库
2. 打开仓库的 **Actions**
3. 选择工作流：`Build luci-app-vnt2 for OpenWrt 24.10 x86_64`
4. 点击 **Run workflow**
5. 输入 `release_tag`，例如：

```text
v1.0.0
```

6. 等待编译完成
7. 在：
   - **Actions Artifacts** 获取构建产物
   - **Releases** 获取自动发布的 ipk 包

---

## LuCI 页面说明

安装完成后，在 OpenWrt 后台中进入：

```text
VPN -> VNT2
```

页面主要包括：

- **基本设置**
  - 配置 `vnt2_cli`
  - 配置 `vnt2_web`
  - 启停服务
  - 上传二进制文件
- **客户端日志**
  - 查看 `/tmp/vnt2-cli.log`
- **Web 日志**
  - 查看 `/tmp/vnt2-web.log`

状态页可查看：
- CLI / Web 运行状态
- 控制端口
- 监听地址
- 版本信息
- 本机信息预览

---

## 二进制文件说明

本 LuCI 插件负责管理 VNT2 服务，但不直接内置所有二进制程序。

通常你需要在 OpenWrt 上准备以下文件：

- `/usr/bin/vnt2_cli`
- `/usr/bin/vnt2_ctrl`
- `/usr/bin/vnt2_web`

如果目标文件不存在，插件的服务脚本会尝试使用上传方式提供的临时程序，并回写到对应配置项中。

---

## 注意事项

### 1. VNT1 与 VNT2 不兼容
请不要把 V1 参数、V1 服务端、V1 客户端配置直接套用到 V2。

### 2. TUN 模式需要内核支持
如果设备缺少 `kmod-tun`，请改用无 TUN 模式或先安装相关模块。

### 3. Web 监听暴露
如果 `vnt2_web` 监听在 `0.0.0.0` 且允许 WAN 访问，请注意安全风险。

### 4. Release 说明为精简模式
当前工作流按要求只在 Release 中展示编译时间，不生成额外发布说明。

---

## 目录结构

```text
luci-app-vnt2/
├─ .github/
│  └─ workflows/
│     └─ build.yml
├─ README.md
└─ luci-app-vnt2/
   ├─ Makefile
   ├─ luasrc/
   │  ├─ controller/
   │  │  └─ vnt2.lua
   │  ├─ model/cbi/
   │  │  ├─ vnt2.lua
   │  │  ├─ vnt2_log.lua
   │  │  └─ vnt2_web_log.lua
   │  └─ view/vnt2/
   │     ├─ vnt2_status.htm
   │     ├─ vnt2-cli_log.htm
   │     └─ vnt2-web_log.htm
   └─ root/
      └─ etc/
         ├─ config/
         │  └─ vnt2
         └─ init.d/
            └─ vnt2
```

---

## 致谢

- VNT2 上游项目：`vnt-dev/vnt`
- V1 LuCI 插件界面参考：`luci-app-vnt-main`

如果后续你还需要，我可以继续补一版：
- 带截图占位说明的 README
- 更适合 GitHub 展示的徽章版 README
- 中英双语 README
