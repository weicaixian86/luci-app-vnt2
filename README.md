# luci-app-vnt2

<p align="center">
  <img alt="OpenWrt" src="https://img.shields.io/badge/OpenWrt-LuCI-blue?logo=openwrt">
  <img alt="VNT2" src="https://img.shields.io/badge/VNT-2.x-32c955">
  <img alt="Status" src="https://img.shields.io/badge/Status-In%20Progress-orange">
</p>

`luci-app-vnt2` 是一个面向 **OpenWrt LuCI** 的 **VNT2 图形化管理插件**，用于在路由器后台统一管理：

- `vnt2_cli`
- `vnt2_ctrl`
- `vnt2_web`
- `vnts2`

当前项目重点是把 **VNT2 客户端 / Web / 服务端** 的常用能力整合到 OpenWrt 后台中，提供更适合路由器场景的配置、启动、状态查看、日志查看、自动下载与网络联动能力。

---

## 项目定位

本仓库中包含多套相关代码，作用如下：

- `需求书-项目说明.md`  
  当前项目需求说明。

- `luci-app-vnt-main/`  
  VNT1 的 LuCI 插件实现，主要作为界面风格和交互参考。

- `luci-app-vnt2/`  
  当前正在开发的 **VNT2 LuCI 插件**。

- `vnt-2/`  
  VNT2 上游客户端相关源码，用于核对参数、行为和版本能力。

- `vnts-2/`  
  VNT2 上游服务端相关源码，用于核对服务端配置和启动方式。

> 注意：  
> **VNT1 与 VNT2 不是同一套协议与参数体系。**  
> 本插件对应的是 **VNT2**，不要直接套用 VNT1 的配置。

---

## 当前已完成功能

### 1. LuCI 菜单与页面入口

安装后可在 OpenWrt 后台进入：

```text
VPN -> VNT2
```

当前菜单包含：

- **基本设置**
- **cli客户端日志**
- **web客户端日志**
- **服务端日志**
- **下载日志**

---

### 2. 三类核心进程统一管理

当前插件已经支持统一管理以下进程：

- `vnt2_cli`：VNT2 客户端主程序
- `vnt2_ctrl`：客户端控制查询程序
- `vnt2_web`：VNT2 Web 客户端管理主程序
- `vnts2`：VNT2 服务端程序

并通过 `/etc/init.d/vnt2` 进行统一启停和 `procd` 守护管理。

---

### 3. 客户端（vnt2_cli）管理

已支持的客户端能力包括：

- 启用/禁用客户端
- 指定 `vnt2_cli` 二进制路径
- 指定 `vnt2_ctrl` 二进制路径
- 使用共享客户端 TOML 配置文件启动（与 `vnt2_web` 共用 `/vnt_config/vnt2_cli_web.toml`）
- 校验客户端 TOML 配置是否合法
- 启动失败时输出到客户端日志
- 状态页显示客户端运行状态、PID、运行时间、CPU、内存
- 通过 `vnt2_ctrl`/CLI 查询：
  - `info`
  - `ips`
  - `clients`
  - `route`
  - 当前启动命令行

---

### 4. Web（vnt2_web）管理

已支持的 Web 能力包括：

- 启用/禁用 `vnt2_web`
- 指定 `vnt2_web` 二进制路径
- 与 `vnt2_cli` 共用客户端运行 TOML：`/vnt_config/vnt2_cli_web.toml`
- 设置监听地址
- 设置监听端口
- 设置日志级别
- 页面中跳转打开原生 `vnt2_web`
- 状态页显示 Web 运行状态、PID、运行时间、CPU、内存
- 状态区底部提供快捷入口：
  - `打开web页面`
  - `查看web日志`
- `打开web页面` 采用浏览器新选项卡打开，避免覆盖当前 LuCI 页面
- 当监听在 `0.0.0.0` / `::` 且允许 WAN 访问时，自动添加防火墙放行规则

---

### 5. 服务端（vnts2）管理

已支持的服务端能力包括：

- 启用/禁用 `vnts2`
- 指定 `vnts2` 二进制路径
- 使用服务端 TOML 配置文件启动
- 校验服务端 TOML 配置文件是否存在
- 状态页显示服务端运行状态、PID、运行时间、CPU、内存
- 状态区底部提供快捷入口：
  - `打开web页面`
  - `查看服务端日志`
  - `查看下载日志`
- 其中 `打开web页面` 位于 `查看服务端日志` 左侧
- `打开web页面` 通过 LuCI 控制器路由跳转到服务端管理页面监听地址，并以浏览器新选项卡打开
- 显示服务端命令行
- 展示并预览服务端配置内容
- 支持服务端端口对应的防火墙联动：
  - TCP
  - QUIC
  - WebSocket
  - Web 管理口

---

### 6. 自动下载二进制程序

当前 init 脚本已经支持 **自动下载缺失程序**。

#### 支持范围

- 客户端包：`vnt2_cli` / `vnt2_ctrl` / `vnt2_web`
- 服务端包：`vnts2`

#### 自动下载特性

- 支持按架构识别下载目标资源
- 支持从 GitHub Releases 获取发行版元数据
- 支持 `latest` 和指定版本 tag
- 支持缓存下载结果
- 支持 zip / tar.gz / tar.xz 等常见压缩包
- 自动解压并安装到：

```text
/usr/bin/
```

#### 默认仓库

- 客户端 / Web：`vnt-dev/vnt`
- 服务端：`vnt-dev/vnts`

#### 下载日志与状态

相关信息会记录到：

- `/tmp/vnt2-download.log`
- `/tmp/vnt2-download-cli.state`
- `/tmp/vnt2-download-web.state`
- `/tmp/vnt2-download-server.state`

LuCI 页面已提供 **下载日志** 查看入口。

---

### 7. 上传程序回退机制

如果自动下载失败，插件还支持回退到本地上传的程序文件。

当前脚本会尝试识别上传后的有效程序文件，并优先安装到：

```text
/usr/bin/
```

同时自动赋予执行权限，并写回对应状态与路径信息。

当前文档与需求基线要求最终生效路径应以 `/usr/bin/` 为准，不应仅依赖 `/tmp` 临时文件长期运行。

这使得在无法联网或 GitHub 下载失败的 OpenWrt 环境中，仍然可以通过网页上传程序来补齐并启动服务。

---

### 8. TUN / 网络 / 防火墙联动

客户端启动时，当前实现已支持根据配置自动处理 OpenWrt 网络和防火墙。

#### TUN 模式
当客户端使用 TUN 模式时，会自动创建：

- `network.VNT2`
- `firewall.vnt2zone`

并按配置生成转发规则，例如：

- VNT2 -> LAN
- VNT2 -> WAN
- LAN -> VNT2
- WAN -> VNT2

同时自动开启：

```text
net.ipv4.ip_forward=1
```

#### 无 TUN 模式
当 `no_tun=1` 时，会自动清理对应的网络和防火墙区配置。

#### Web / 服务端端口放行
- `vnt2_web` 可按配置开放 WAN 访问端口
- `vnts2` 可分别开放 TCP / QUIC / WS / Web 端口

---

### 9. 状态页信息聚合

当前状态接口已经能够聚合以下信息并提供给 LuCI 页面展示：

#### 客户端
- 是否运行
- PID
- 运行时长
- CPU 占用
- 内存占用
- 当前版本
- 最新版本
- 控制端口
- 配置文件路径
- 配置内容预览
- `info` / `ips` 信息预览

#### Web
- 是否运行
- PID
- 运行时长
- CPU 占用
- 内存占用
- 当前版本
- 监听地址
- 监听端口
- 自动拼接访问 URL
- 状态区快捷入口：
  - `打开web页面`
  - `查看web日志`

#### 服务端
- 是否运行
- PID
- 运行时长
- CPU 占用
- 内存占用
- 当前版本
- 最新版本
- TCP / QUIC / WS / Web 绑定地址
- 网络配置
- 用户名
- 白名单
- Peer Server
- 自定义网段
- 服务端配置文件路径
- 配置内容预览
- 状态区快捷入口：
  - `打开web页面`
  - `查看服务端日志`
  - `查看下载日志`
- `打开web页面` 使用新选项卡打开服务端管理页面监听地址

#### 下载状态
- CLI 下载状态
- Web 下载状态
- 服务端下载状态
- 下载日志大小

---

### 10. 多类日志查看

当前插件已提供以下日志查看能力：

- 客户端日志：`/tmp/vnt2-cli.log`
- Web 日志：`/tmp/vnt2-web.log`
- 服务端日志：`/tmp/vnts2.log`
- 下载日志：`/tmp/vnt2-download.log`

并支持在 LuCI 页面中读取与清空对应日志。

---

## 目录结构

当前插件目录结构如下：

```text
luci-app-vnt2/
├─ README.md
└─ luci-app-vnt2/
   ├─ Makefile
   ├─ luasrc/
   │  ├─ controller/
   │  │  └─ vnt2.lua
   │  ├─ model/
   │  │  ├─ vnt2_toml.lua
   │  │  └─ cbi/
   │  │     ├─ vnt2.lua
   │  │     ├─ vnt2_log.lua
   │  │     ├─ vnt2_web_log.lua
   │  │     ├─ vnt2_server_log.lua
   │  │     └─ vnt2_download_log.lua
   │  └─ view/
   │     └─ vnt2/
   │        ├─ vnt2_status.htm
   │        ├─ vnt2-cli_log.htm
   │        ├─ vnt2-web_log.htm
   │        ├─ vnts2_log.htm
   │        ├─ vnt2_download_log.htm
   │        ├─ other_upload.htm
   │        └─ other_dvalue.htm
   └─ root/
      └─ etc/
         ├─ config/
         │  └─ vnt2
         └─ init.d/
            └─ vnt2
```

> 说明：  
> 当前目录中也存在一些命名相近的历史视图文件，例如 `vnt2-download_log.htm` / `vnt2-web_log.htm`。  
> README 以上述实际使用的主文件为主说明。

---

## 依赖说明

根据当前 `Makefile`，插件依赖如下：

- `luci-compat`
- `curl`
- `ca-bundle`
- `unzip`

即：

```makefile
LUCI_DEPENDS:=+luci-compat +curl +ca-bundle +unzip
```

### 依赖作用简述

- `luci-compat`：兼容 LuCI 传统 Lua 体系
- `curl`：用于访问 GitHub Releases / 下载程序
- `ca-bundle`：HTTPS 证书支持
- `unzip`：解压 zip 发行包

> 如果你的系统缺少 `tar`、`busybox unzip` 等能力，自动下载解压成功率也会受到影响。

---

## 安装方式

### 1. 在 OpenWrt 源码中编译

将目录放到 OpenWrt 的 `package` 或自定义 feed 中，例如：

```sh
git clone <your-repo-url> package/luci-app-vnt2
```

然后执行：

```sh
make menuconfig
```

在菜单中选择：

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

### 2. 安装编译后的 ipk

如果你已经编译出 ipk，可在 OpenWrt 中执行：

```sh
opkg install luci-app-vnt2_*.ipk
```

安装后脚本会自动：

- 给 `/etc/init.d/vnt2` 增加执行权限
- 启用 `vnt2` 服务

---

## 卸载与配置保留

当前 `Makefile` 中已实现卸载前配置备份和重装恢复逻辑：

### 卸载前
会把配置文件：

```text
/etc/config/vnt2
```

移动到：

```text
/tmp/vnt2_backup
```

### 重新安装后
如果检测到 `/tmp/vnt2_backup`，会自动恢复为：

```text
/etc/config/vnt2
```

因此在 **不重启设备** 的前提下，重新安装插件通常可以保留原有配置。

---

## 运行后涉及的主要文件

### 配置文件
- `/etc/config/vnt2`
- `/vnt_config/vnt2_cli_web.toml`
- `/etc/config/vnts2.toml`

其中：
- `vnt2_cli` 与 `vnt2_web` 共用 `/vnt_config/vnt2_cli_web.toml`
- `vnts2` 独立使用 `/etc/config/vnts2.toml`
- 若 `/vnt_config/` 不存在，init 脚本会自动创建该目录，并进行权限处理以尽量保证可写

### 二进制文件
- `/usr/bin/vnt2_cli`
- `/usr/bin/vnt2_ctrl`
- `/usr/bin/vnt2_web`
- `/usr/bin/vnts2`

### 日志文件
- `/tmp/vnt2-cli.log`
- `/tmp/vnt2-web.log`
- `/tmp/vnts2.log`
- `/tmp/vnt2-download.log`

### 运行标记
- `/tmp/vnt2_cli_time`
- `/tmp/vnt2_web_time`
- `/tmp/vnts2_time`

---

## 当前适用场景

当前版本更适合以下场景：

- 在 OpenWrt 上图形化管理 VNT2 客户端
- 在路由器上托管 `vnt2_web`
- 在 OpenWrt 上直接运行 `vnts2`
- 设备没有预装二进制程序，希望通过自动下载补齐
- 设备无法自动下载，希望通过网页上传程序回退运行
- 需要查看 VNT2 客户端 / 服务端运行状态与日志

---

## 当前限制与说明

### 1. 项目仍处于持续完善阶段
README 描述的是**当前已完成实现**，并不代表所有需求都已最终收尾。

### 2. 自动下载依赖外网访问
如果 OpenWrt 设备无法访问 GitHub Releases，则自动下载会失败，此时可改用上传方式。

### 3. TUN 模式依赖内核与系统环境
若设备不支持 TUN，建议改用 `no_tun` 模式。

### 4. Web / 服务端开放 WAN 需谨慎
如果你将 `vnt2_web` 或 `vnts2` 的端口暴露到 WAN，请自行评估安全风险。

### 5. 版本号与上游资源命名可能变化
当前下载逻辑已尽量兼容多种命名方式，但上游 Release 资源命名规则变化时，仍可能需要同步调整脚本。

---

## 后续可继续补充的方向

以下内容适合后续继续完善：

- README 增加页面截图
- 增加 OpenWrt 版本适配说明
- 增加常见问题 FAQ
- 增加从 UCI 到 TOML 的字段映射说明
- 增加完整的客户端 / 服务端配置示例
- 增加更细化的编译与打包说明

---

## 致谢

- VNT2 上游客户端项目：一不小心 `vnt-dev/vnt`
- VNT2 上游服务端项目：一不小心 `vnt-dev/vnts`
- VNT1 LuCI 插件参考：lmq8267 `luci-app-vnt-main`
