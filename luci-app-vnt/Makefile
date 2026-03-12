include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Support for VNT2 (Virtual Network Tunnel V2)
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+bash +iproute2

PKG_NAME:=luci-app-vnt2
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk

define Build/Compile
    git clone https://github.com/vnt-dev/vnt.git $(BUILD_DIR)/vnt
    cd $(BUILD_DIR)/vnt && git checkout v2
    cd $(BUILD_DIR)/vnt && GOOS=linux GOARCH=$(ARCH) go build -o vnt2 ./cmd/vnt
    mkdir -p $(PKG_BUILD_DIR)/root/usr/bin
    cp $(BUILD_DIR)/vnt/vnt2 $(PKG_BUILD_DIR)/root/usr/bin/
endef

define Package/luci-app-vnt2/install
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
    $(INSTALL_DATA) ./luasrc/controller/vnt2.lua $(1)/usr/lib/lua/luci/controller/
    
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
    $(INSTALL_DATA) ./luasrc/model/cbi/vnt2.lua $(1)/usr/lib/lua/luci/model/cbi/
    
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/vnt2
    $(INSTALL_DATA) ./luasrc/view/vnt2/status.htm $(1)/usr/lib/lua/luci/view/vnt2/
    
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_CONF) ./root/etc/config/vnt2 $(1)/etc/config/
    
    $(INSTALL_DIR) $(1)/etc/init.d
    $(INSTALL_BIN) ./root/etc/init.d/vnt2 $(1)/etc/init.d/
    
    $(INSTALL_DIR) $(1)/usr/bin
    $(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/vnt2 $(1)/usr/bin/
endef

$(eval $(call BuildPackage,luci-app-vnt2))
