#
# Copyright (C) 2008-2024 The LuCI Team
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vnt2web
PKG_VERSION:=2.0.53
PKG_RELEASE:=2

LUCI_TITLE:=luci-app-vnt2web - LuCI support for VNT2 Web
LUCI_DESCRIPTION:=luci-app-vnt2web OpenWrt LuCI application for managing the VNT2 Web client
LUCI_DEPENDS:=+luci-base +luci-compat +kmod-tun +curl +ca-bundle +unzip
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/conffiles
/etc/config/vnt2
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] && [ -x /etc/init.d/vnt2-upload-worker ] ; then
  /etc/init.d/vnt2-upload-worker stop >/dev/null 2>&1
  /etc/init.d/vnt2-upload-worker disable >/dev/null 2>&1
fi
if [ -z "$${IPKG_INSTROOT}" ] && [ -x /etc/init.d/vnt2-worker ] ; then
  /etc/init.d/vnt2-worker stop >/dev/null 2>&1
  /etc/init.d/vnt2-worker disable >/dev/null 2>&1
fi
if [ -z "$${IPKG_INSTROOT}" ] && [ -x /etc/init.d/vnt2-version-worker ] ; then
  /etc/init.d/vnt2-version-worker stop >/dev/null 2>&1
  /etc/init.d/vnt2-version-worker disable >/dev/null 2>&1
fi
if [ -f /etc/config/vnt2 ] ; then
  echo "备份vnt2配置文件 /etc/config/vnt2 到 /tmp/vnt2_backup"
  echo "不重启设备前重新安装 luci-app-vnt2web 可保留原配置"
  mv -f /etc/config/vnt2 /tmp/vnt2_backup
fi
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod 0755 \
  "$${IPKG_INSTROOT}/etc/init.d/vnt2" \
  "$${IPKG_INSTROOT}/etc/init.d/vnt2-upload-worker" \
  "$${IPKG_INSTROOT}/etc/init.d/vnt2-worker" \
  "$${IPKG_INSTROOT}/etc/init.d/vnt2-version-worker" \
  "$${IPKG_INSTROOT}/usr/libexec/vnt2/restart-worker" \
  "$${IPKG_INSTROOT}/usr/libexec/vnt2/upload-worker" \
  "$${IPKG_INSTROOT}/usr/libexec/vnt2/version-worker" >/dev/null 2>&1
if [ -f /tmp/vnt2_backup ] ; then
  echo "发现 vnt2 备份配置文件 /tmp/vnt2_backup，开始恢复到 /etc/config/vnt2"
  mv -f /tmp/vnt2_backup /etc/config/vnt2
  echo "请前往 VPN -> VNT2 页面按需重启服务"
fi
if [ -z "$${IPKG_INSTROOT}" ] ; then
  /etc/init.d/vnt2 enable >/dev/null 2>&1
  /etc/init.d/vnt2-upload-worker enable >/dev/null 2>&1
  /etc/init.d/vnt2-upload-worker restart >/dev/null 2>&1
  /etc/init.d/vnt2-worker enable >/dev/null 2>&1
  /etc/init.d/vnt2-worker restart >/dev/null 2>&1
  /etc/init.d/vnt2-version-worker enable >/dev/null 2>&1
  /etc/init.d/vnt2-version-worker restart >/dev/null 2>&1
fi
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
