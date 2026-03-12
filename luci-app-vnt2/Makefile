# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_VERSION:=1.2.16
PKG_RELEASE:=1

LUCI_TITLE:=LuCI Support for VNT2 (Virtual Network Tunnel)
LUCI_DEPENDS:=+kmod-tun +luci-compat  # 仅保留核心依赖，移除bash/iproute2
LUCI_PKGARCH:=all  # LuCI插件为全架构包

PKG_NAME:=luci-app-vnt2

# 预卸载脚本：备份V2配置，避免丢失
define Package/$(PKG_NAME)/prerm
#!/bin/sh
if [ -f /etc/config/vnt2 ] ; then
  echo "备份vnt2配置文件/etc/config/vnt2到/tmp/vnt2_backup"
  echo "不重启设备之前再次安装luci-app-vnt2 配置不丢失,不用重新配置"
  mv -f /etc/config/vnt2 /tmp/vnt2_backup
fi
endef

# 安装后脚本：恢复配置+赋予启动脚本执行权限
define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod +x /etc/init.d/vnt2
if [ -f /tmp/vnt2_backup ] ; then
  echo "发现vnt2备份配置文件/tmp/vnt2_backup，开始恢复到/etc/config/vnt2"
  mv -f /tmp/vnt2_backup /etc/config/vnt2
  echo "请前往 VPN - VNT2 界面进行重启插件"
fi
endef

include $(TOPDIR)/feeds/luci/luci.mk

# 无需自定义install段！luci.mk会自动安装luasrc/root下的所有文件
# call BuildPackage - OpenWrt buildroot signature
