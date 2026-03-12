include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Support for VNT2 (Virtual Network Tunnel)
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base +luci-compat +bash +iproute2

PKG_NAME:=luci-app-vnt2
PKG_VERSION:=1.2.16
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk

# 安装VNT2二进制文件和配置
define Package/luci-app-vnt2/install
	# 安装VNT-CLI二进制
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./root/usr/sbin/vnt-cli $(1)/usr/sbin/
	
	# 安装UCI配置文件
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/vnt2 $(1)/etc/config/
	
	# 安装启动脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/vnt2 $(1)/etc/init.d/
	chmod +x $(1)/etc/init.d/vnt2
	
	# 安装LuCI控制器
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/vnt2.lua $(1)/usr/lib/lua/luci/controller/
	
	# 安装CBI配置界面
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luasrc/model/cbi/vnt2.lua $(1)/usr/lib/lua/luci/model/cbi/
	
	# 新增：安装状态页面模板
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/vnt2
	$(INSTALL_DATA) ./luasrc/view/vnt2/status.htm $(1)/usr/lib/lua/luci/view/vnt2/
	
	# 新增：安装UCI初始化脚本
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/luci-vnt2 $(1)/etc/uci-defaults/
	chmod +x $(1)/etc/uci-defaults/luci-vnt2
endef

$(eval $(call BuildPackage,luci-app-vnt2))
