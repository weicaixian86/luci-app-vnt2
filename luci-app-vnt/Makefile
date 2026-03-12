include $(TOPDIR)/rules.mk

# LuCI 插件基本信息
LUCI_TITLE:=LuCI Support for VNT2 (Virtual Network Tunnel V2)
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+bash +iproute2 +golang  # 新增 golang 依赖，确保编译环境有 Go

# 插件版本与命名
PKG_NAME:=luci-app-vnt2
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

# 引入 LuCI 编译规则
include $(TOPDIR)/feeds/luci/luci.mk

# 编译 V2 核心二进制（修复依赖问题）
define Build/Compile
    # 克隆 V2 核心源码
    git clone --depth 1 --branch v2 https://github.com/vnt-dev/vnt.git $(BUILD_DIR)/vnt
    # 拉取 Go 依赖（关键修复：解决「找不到包」报错）
    cd $(BUILD_DIR)/vnt && go mod tidy
    # 编译 V2 二进制（适配 OpenWrt 架构）
    cd $(BUILD_DIR)/vnt && GOOS=linux GOARCH=$(ARCH) CGO_ENABLED=0 go build -ldflags "-s -w" -o vnt2 ./cmd/vnt
    # 创建目录并拷贝二进制
    mkdir -p $(PKG_BUILD_DIR)/root/usr/bin
    cp $(BUILD_DIR)/vnt/vnt2 $(PKG_BUILD_DIR)/root/usr/bin/
    # 赋予执行权限
    chmod +x $(PKG_BUILD_DIR)/root/usr/bin/vnt2
endef

# 安装插件文件（修复启动脚本权限）
define Package/luci-app-vnt2/install
    # 安装 LuCI 控制器
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
    $(INSTALL_DATA) ./luasrc/controller/vnt2.lua $(1)/usr/lib/lua/luci/controller/
    
    # 安装 CBI 配置页面
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
    $(INSTALL_DATA) ./luasrc/model/cbi/vnt2.lua $(1)/usr/lib/lua/luci/model/cbi/
    
    # 安装前端状态页面
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/vnt2
    $(INSTALL_DATA) ./luasrc/view/vnt2/status.htm $(1)/usr/lib/lua/luci/view/vnt2/
    
    # 安装 UCI 配置模板
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_CONF) ./root/etc/config/vnt2 $(1)/etc/config/
    
    # 安装启动脚本（新增执行权限）
    $(INSTALL_DIR) $(1)/etc/init.d
    $(INSTALL_BIN) ./root/etc/init.d/vnt2 $(1)/etc/init.d/
    chmod +x $(1)/etc/init.d/vnt2  # 关键修复：赋予启动脚本执行权限
    
    # 安装 V2 二进制文件
    $(INSTALL_DIR) $(1)/usr/bin
    $(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/vnt2 $(1)/usr/bin/
endef

# 编译后清理（可选，避免残留）
define Build/Clean
    rm -rf $(BUILD_DIR)/vnt
    rm -rf $(PKG_BUILD_DIR)/root
endef

# 生成 IPK 包
$(eval $(call BuildPackage,luci-app-vnt2))
