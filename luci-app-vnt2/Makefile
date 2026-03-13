include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vnt2
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Your Name <your@email.com>
PKG_LICENSE:=GPL-3.0

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-vnt2
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for VNT2 (Virtual Network Tunnel v2)
  DEPENDS:=+luci-base +luci-compat +vnt2 +vnts2 +kmod-tun
  URL:=https://github.com/weicaixian86/luci-app-vnt2
endef

define Package/luci-app-vnt2/description
  LuCI configuration interface for VNT2 client and server (vnt2-cli & vnts2)
endef

define Build/Compile
endef

define Package/luci-app-vnt2/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luasrc/model/cbi/*.lua $(1)/usr/lib/lua/luci/model/cbi/

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/vnt2
	$(INSTALL_DATA) ./luasrc/view/vnt2/*.htm $(1)/usr/lib/lua/luci/view/vnt2/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/vnt2 $(1)/etc/config/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/vnt2 $(1)/etc/init.d/vnt2
endef

$(eval $(call BuildPackage,luci-app-vnt2))
