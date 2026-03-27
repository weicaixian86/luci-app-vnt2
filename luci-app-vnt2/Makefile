
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
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
