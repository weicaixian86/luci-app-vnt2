
#
# Copyright (C) 2024 OpenWrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=VNT2 - Virtual Network Tool V2
LUCI_DEPENDS:=+libc +libopenssl +libustream-openssl +librt +libpthread +kmod-tun
LUCI_PKGARCH:=all

PKG_VERSION:=1.0.0
PKG_RELEASE:=2

define Package/luci-app-vnt2/postinst
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] || { chmod 755 /etc/init.d/vnt2; /etc/init.d/vnt2 enable; }
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
