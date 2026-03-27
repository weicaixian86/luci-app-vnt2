#
# Copyright (C) 2008-2014 The LuCI Team <luci@lists.subsignal.org>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.luci

PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for vnt2
LUCI_DEPENDS:=+kmod-tun +luci-compat
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-vnt2

define Package/$(PKG_NAME)/prerm
#!/bin/sh
if [ -f /etc/config/vnt2 ] ; then
  echo "备份vnt2配置文件/etc/config/vnt2到/tmp/vnt2_backup"
  echo "不重启设备之前再次安装luci-app-vnt2 配置不丢失,不用重新配置"
  mv -f /etc/config/vnt2 /tmp/vnt2_backup
fi
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod +x /etc/init.d/vnt2
if [ -f /tmp/vnt2_backup ] ; then
  echo "发现vnt2备份配置文件/tmp/vnt2_backup，開始恢復到/etc/config/vnt2"
  mv -f /tmp/vnt2_backup /etc/config/vnt2
  echo "請前往 VPN - VNT2 界面進行重啟插件"
fi
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
