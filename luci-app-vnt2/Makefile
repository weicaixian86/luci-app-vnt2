include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Support for VNT2
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base +luci-compat
PKG_NAME:=luci-app-vnt2
PKG_VERSION:=1.2.16
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk

# 安装VNT-CLI二进制（需提前编译适配OpenWRT的版本）
define Package/luci-app-vnt2/install
    $(INSTALL_DIR) $(1)/usr/sbin
    $(INSTALL_BIN) ./files/usr/sbin/vnt-cli $(1)/usr/sbin/
    $(INSTALL_DIR) $(1)/usr/bin
    $(INSTALL_BIN) ./files/usr/bin/vnt2.sh $(1)/usr/bin/
endef

$(eval $(call BuildPackage,luci-app-vnt2))
