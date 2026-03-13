include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-vnt2
PKG_VERSION:=2.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Your Name <your@email.com>

LUCI_TITLE:=LuCI Support for VNT2 (vnt2-cli/vnts2)
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base +luci-compat +wget-ssl +unzip +tar +curl

define Package/$(PKG_NAME)/description
    LuCI interface for VNT2 (vnt2-cli/vnts2) - 异地组网/内网穿透工具
endef

include $(TOPDIR)/feeds/luci/luci.mk

# 修复：确保所有LuCI文件被正确复制到打包目录
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	# 复制luasrc和root目录到构建目录
	cp -r ./luasrc $(PKG_BUILD_DIR)/
	cp -r ./root $(PKG_BUILD_DIR)/
endef

# 修复：指定所有文件的安装路径（解决Model not found）
define Package/$(PKG_NAME)/install
	# 安装控制器
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luasrc/controller/vnt2.lua $(1)/usr/lib/lua/luci/controller/
	
	# 安装CBI模型（关键：解决client.lua not found）
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/vnt2
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luasrc/model/cbi/vnt2/client.lua $(1)/usr/lib/lua/luci/model/cbi/vnt2/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luasrc/model/cbi/vnt2/server.lua $(1)/usr/lib/lua/luci/model/cbi/vnt2/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luasrc/model/cbi/vnt2/log_client.lua $(1)/usr/lib/lua/luci/model/cbi/vnt2/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luasrc/model/cbi/vnt2/log_server.lua $(1)/usr/lib/lua/luci/model/cbi/vnt2/
	
	# 安装视图模板
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/vnt2
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/luasrc/view/vnt2/status.htm $(1)/usr/lib/lua/luci/view/vnt2/
	
	# 安装root目录文件（配置/脚本/权限）
	$(CP) $(PKG_BUILD_DIR)/root/* $(1)/
	
	# 设置脚本执行权限
	$(chmod) 755 $(1)/etc/init.d/vnt2
	$(chmod) 755 $(1)/etc/uci-defaults/99_luci-app-vnt2
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
