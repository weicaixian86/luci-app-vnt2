# luci-app-vnt2web

这是一个仅用于管理 `vnt2_web` 客户端的 OpenWrt LuCI 插件。

运行时配置文件固定为 `/etc/config/vnt2.toml`。

## 包名称说明

OpenWrt 软件包管理器中的实际包名固定为：

- `luci-app-vnt2web`

无论是在 `系统 -> 软件包` 页面中搜索，还是使用 `opkg` / `apk` 查询，实际包名都应当使用 `luci-app-vnt2web`。

## 发布文件说明

GitHub Release 中发布的安装文件，直接保留 OpenWrt 实际生成的文件名。
工作流不会改写版本号、发布号或架构，文件名由 OpenWrt 打包过程决定，
但软件包名前缀始终为：

- `luci-app-vnt2web`

因此不同 SDK 版本下的文件名可能不同，例如：

- `luci-app-vnt2web_2.0.53-2_x86_64.ipk`
- `luci-app-vnt2web-2.0.53-r2.apk`

请以 Release 页面中实际列出的文件名为准，不要按固定模板猜测。

## 上传与版本说明

- 手动上传由 LuCI 暂存到 `/etc/vnt2/upload`，随后交给后台 worker 校验并安装，不会阻塞页面请求。
- 安装成功后程序位于 `/usr/bin/vnt2_web`，并自动排队重启服务。
- 本地版本来自 `/etc/config/vnt2-web.version`；若程序被替换或修改，本地版本会显示为空，而不是显示过期版本。

## 安装方法

### OpenWrt 24.10.x

将 `.ipk` 文件上传到路由器，例如上传到 `/tmp/`，然后执行：

```sh
opkg install /tmp/luci-app-vnt2web*.ipk
opkg info luci-app-vnt2web
opkg list-installed | grep luci-app-vnt2web
```

### OpenWrt 25.12.0

将 `.apk` 文件上传到路由器，例如上传到 `/tmp/`，然后执行：

```sh
apk add --allow-untrusted /tmp/luci-app-vnt2web*.apk
apk info luci-app-vnt2web
```
## 卸载方法

OpenWrt 24.10.x：

```sh
opkg remove luci-app-vnt2web
```

OpenWrt 25.12.0：

```sh
apk del luci-app-vnt2web
```

## 在 OpenWrt 源码树中编译

本仓库根目录下仍有一层插件源码目录。将其中的 `luci-app-vnt2web/` 放入 OpenWrt 的 `package/` 目录，或放入自定义 feed 中，然后执行：

```sh
git clone <你的仓库地址> /tmp/luci-app-vnt2web-src
cp -a /tmp/luci-app-vnt2web-src/luci-app-vnt2web package/luci-app-vnt2web
make menuconfig
make package/luci-app-vnt2web/compile V=s
```

编译完成后：

- OpenWrt 24.10.x 生成 `.ipk`
- OpenWrt 25.12.0 生成 `.apk`

## LuCI 菜单位置

安装完成后，在 LuCI 中进入：

```text
VPN -> VNT2
```
