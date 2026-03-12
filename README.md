# luci-app-vnt2
OpenWrt LuCI plugin for VNT v2 (Virtual Network Tunnel)

## 安装
1. 编译插件：`make package/luci-app-vnt2/compile V=s`
2. 安装IPK：`opkg install luci-app-vnt2_2.0.0-1_all.ipk`

## 使用
- 登录OpenWrt LuCI → 网络 → VNT2
- 填写服务器地址、端口、Token，启用即可
