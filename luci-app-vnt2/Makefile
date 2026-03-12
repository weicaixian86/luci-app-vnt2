# 引入 OpenWrt 基础编译规则
include $(TOPDIR)/rules.mk

# ===================== 插件基础信息 =====================
# 插件名称（必须和目录名一致）
PKG_NAME:=luci-app-vnt2
# 插件版本号
PKG_VERSION:=2.0.0
# 插件发布版本
PKG_RELEASE:=1

# LuCI 插件核心配置
LUCI_TITLE:=LuCI Support for VNT2 (Virtual Network Tunnel V2)  # 插件显示名称
LUCI_PKGARCH:=all                                             # 架构兼容（all 表示全架构）
LUCI_DEPENDS:=+bash +iproute2 +golang                         # 编译/运行依赖（新增 golang 确保编译环境）

# 引入 LuCI 编译规则
include $(TOPDIR)/feeds/luci/luci.mk

# ===================== 编译 VNT2 核心二进制 =====================
define Build/Compile
    # 克隆 VNT2 核心源码（仅克隆 v2 分支，减少体积）
    git clone --depth 1 --branch v2 https://github.com/vnt-dev/vnt.git $(BUILD_DIR)/vnt
    
    # 拉取 Go 依赖（解决「找不到包」编译错误，关键修复）
    cd $(BUILD_DIR)/vnt && go mod tidy
    
    # 编译 VNT2 二进制（适配 OpenWrt 架构，关闭 CGO 减少依赖）
    cd $(BUILD_DIR)/vnt && GOOS=linux GOARCH=$(ARCH) CGO_ENABLED=0 go build -ldflags "-s -w" -o vnt2 ./cmd/vnt
    
    # 创建二进制存放目录
    mkdir -p $(PKG_BUILD_DIR)/root/usr/bin
    
    # 拷贝编译好的二进制文件
    cp $(BUILD_DIR)/vnt/vnt2 $(PKG_BUILD_DIR)/root/usr/bin/
    
    # 赋予二进制可执行权限
    chmod +x $(PKG_BUILD_DIR)/root/usr/bin/vnt2
endef

# ===================== 安装插件文件 =====================
define Package/luci-app-vnt2/install
    # 1. 安装 LuCI 控制器文件
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
    $(INSTALL_DATA) ./luasrc/controller/vnt2.lua $(1)/usr/lib/lua/luci/controller/
    
    # 2. 安装 CBI 配置页面文件
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
    $(INSTALL_DATA) ./luasrc/model/cbi/vnt2.lua $(1)/usr/lib/lua/luci/model/cbi/
    
    # 3. 安装前端状态页面文件
    $(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/vnt2
    $(INSTALL_DATA) ./luasrc/view/vnt2/status.htm $(1)/usr/lib/lua/luci/view/vnt2/
    
    # 4. 安装 UCI 配置模板
    $(INSTALL_DIR) $(1)/etc/config
    $(INSTALL_CONF) ./root/etc/config/vnt2 $(1)/etc/config/
    
    # 5. 安装启动脚本（并赋予执行权限，关键修复）
    $(INSTALL_DIR) $(1)/etc/init.d
    $(INSTALL_BIN) ./root/etc/init.d/vnt2 $(1)/etc/init.d/
    chmod +x $(1)/etc/init.d/vnt2
    
    # 6. 安装 VNT2 核心二进制文件
    $(INSTALL_DIR) $(1)/usr/bin
    $(INSTALL_BIN) $(PKG_BUILD_DIR)/root/usr/bin/vnt2 $(1)/usr/bin/
endef

# ===================== 编译后清理（可选，避免残留） =====================
define Build/Clean
    rm -rf $(BUILD_DIR)/vnt
    rm -rf $(PKG_BUILD_DIR)/root
endef

# 生成 IPK 包（OpenWrt 必备）
$(eval $(call BuildPackage,luci-app-vnt2))
