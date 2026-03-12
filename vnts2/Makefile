# OpenWRT 编译配置：VNT2 服务端（vnts2）
# 路径：luci-app-vnt2/vnts2/Makefile
include $(TOPDIR)/rules.mk

# ========== 核心配置（适配 V2 命名） ==========
PKG_NAME:=vnts2
PKG_VERSION:=1.2.12  # 保持和 V1 一致的版本号，如需升级可修改
PKG_RELEASE:=1       # 包发布版本，首次为1，修改后递增

# ========== 架构适配（和 V1 一致，覆盖主流 OpenWRT 架构） ==========
ifeq ($(ARCH),mipsel)
	APP_ARCH:=mipsel-unknown-linux-musl
endif
ifeq ($(ARCH),mips)
	APP_ARCH:=mips-unknown-linux-musl
endif
ifeq ($(ARCH),arm)
	APP_ARCH:=arm-unknown-linux-musleabi
endif
ifeq ($(BOARD),kirkwood)
	APP_ARCH:=arm-unknown-linux-musleabi
endif
ifeq ($(ARCH),armv7)
	APP_ARCH:=armv7-unknown-linux-musleabi
endif
ifeq ($(ARCH),aarch64)
	APP_ARCH:=aarch64-unknown-linux-musl
endif
ifeq ($(ARCH),arm64)
	APP_ARCH:=aarch64-unknown-linux-musl
endif
ifeq ($(ARCH),armv8)
	APP_ARCH:=aarch64-unknown-linux-musl
endif
# i386 架构特殊适配版本号（和 V1 一致）
ifeq ($(ARCH),i386)
	PKG_VERSION:=1.2.11
	APP_ARCH:=i686-unknown-linux-musl
endif
ifeq ($(ARCH),x86_64)
	APP_ARCH:=x86_64-unknown-linux-musl
endif

# 编译目录（适配 vnts2 命名）
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

# 引入 OpenWRT 包编译核心规则
include $(INCLUDE_DIR)/package.mk

# ========== 包基本信息（适配 V2 命名） ==========
define Package/$(PKG_NAME)
	SECTION:=net               # 包分类：网络类
	CATEGORY:=Network          # LuCI 后台显示分类：Network
	TITLE:=VNT2 Server         # 包标题（V2 标识）
	SUBMENU:=VPN               # 子分类：VPN（可选，更易查找）
	# 依赖：仅支持指定架构（和 V1 一致）
	DEPENDS:=@(i386||x86_64||arm||aarch64||mipsel||mips)
	URL:=https://github.com/vnt-dev/vnts  # 保持原源码地址，如需 V2 源码可修改
endef

# ========== 包描述（适配 V2 命名） ==========
define Package/$(PKG_NAME)/description
  V2版本 简便高效的异地组网、内网穿透工具（服务端）
  VNT2 Server - Efficient VPN for LAN penetration and remote networking
endef

# ========== 构建准备：下载预编译包（适配 vnts2 命名） ==========
define Build/Prepare
	# 创建编译目录（防止目录不存在）
	mkdir -p $(PKG_BUILD_DIR)
	# 分支1：i386 架构下载 1.2.11 版本（无v前缀）
	[ "$(ARCH)" = "i386" ] && [ ! -f $(PKG_BUILD_DIR)/$(PKG_NAME)-$(APP_ARCH).tar.gz ] && \
		wget https://github.com/vnt-dev/vnts/releases/download/$(PKG_VERSION)/vnts-$(APP_ARCH)-$(PKG_VERSION).tar.gz -O $(PKG_BUILD_DIR)/$(PKG_NAME)-$(APP_ARCH).tar.gz || true
	# 分支2：非 i386 架构下载 1.2.12 版本（带v前缀）
	[ "$(ARCH)" != "i386" ] && [ ! -f $(PKG_BUILD_DIR)/$(PKG_NAME)-$(APP_ARCH).tar.gz ] && \
		wget https://github.com/vnt-dev/vnts/releases/download/v$(PKG_VERSION)/vnts-$(APP_ARCH)-v$(PKG_VERSION).tar.gz -O $(PKG_BUILD_DIR)/$(PKG_NAME)-$(APP_ARCH).tar.gz || true
	# 解压预编译包到编译目录
	tar -xzvf $(PKG_BUILD_DIR)/$(PKG_NAME)-$(APP_ARCH).tar.gz -C $(PKG_BUILD_DIR)
	# 重命名二进制文件为 vnts2（适配 V2 命名）
	mv $(PKG_BUILD_DIR)/vnts $(PKG_BUILD_DIR)/vnts2 || true
endef

# ========== 编译阶段：空（预编译包无需编译） ==========
define Build/Compile
endef

# ========== 安装阶段：部署 vnts2 到系统（适配 V2 命名） ==========
define Package/$(PKG_NAME)/install
	# 创建目标目录
	$(INSTALL_DIR) $(1)/usr/bin
	# 安装 vnts2 二进制文件
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/vnts2 $(1)/usr/bin/vnts2
	# 可选：创建软链接兼容 V1 命令（如需兼容旧脚本）
	# ln -s /usr/bin/vnts2 $(1)/usr/bin/vnts || true
endef

# ========== 注册包编译目标（OpenWRT 必须） ==========
$(eval $(call BuildPackage,$(PKG_NAME)))
