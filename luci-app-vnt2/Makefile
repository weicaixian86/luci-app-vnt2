#
# Copyright (C) 2008-2024 The LuCI Team
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vnt2
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for VNT2
LUCI_DESCRIPTION:=OpenWrt LuCI application for managing VNT2 CLI/CTRL/Web services
LUCI_DEPENDS:=+luci-compat +kmod-tun +libopenssl +libustream-openssl
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/prerm
#!/bin/sh
if [ -f /etc/config/vnt2 ] ; then
  echo "备份vnt2配置文件 /etc/config/vnt2 到 /tmp/vnt2_backup"
  echo "不重启设备前重新安装 luci-app-vnt2 可保留原配置"
  mv -f /etc/config/vnt2 /tmp/vnt2_backup
fi
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod +x /etc/init.d/vnt2 >/dev/null 2>&1
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/vnt2 enable >/dev/null 2>&1
if [ -f /tmp/vnt2_backup ] ; then
  echo "发现 vnt2 备份配置文件 /tmp/vnt2_backup，开始恢复到 /etc/config/vnt2"
  mv -f /tmp/vnt2_backup /etc/config/vnt2
  echo "请前往 VPN -> VNT2 页面按需重启服务"
fi
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
