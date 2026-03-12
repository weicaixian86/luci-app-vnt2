# OpenWRT 编译配置：VNT2 客户端（vnt2-cli）
# 路径：luci-app-vnt2/vnt2/Makefile
include $(TOPDIR)/rules.mk

# ========== V2 核心基础配置 ==========
PKG_NAME:=vnt2                  # 包名（V2 标识，避免和 V1 冲突）
PKG_VERSION:=1.2.16             # 保持和 V1 客户端一致的版本号，如需升级可修改
PKG_RELEASE:=1                  # 包发布版本号，首次为1，修改后递增

# ========== 架构适配（覆盖 OpenWRT 主流硬件，和 V1 完全一致） ==========
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
ifeq ($(ARCH),i386)
	APP_ARCH:=i686-unknown-linux-musl
endif
ifeq ($(ARCH),x86_64)
	APP_ARCH:=x86_64-unknown-linux-musl
endif

# 编译临时目录（适配 V2 命名，隔离 V1 编译文件）
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

# 引入 OpenWRT 包编译核心规则（必须）
include $(INCLUDE_DIR)/package.mk

# ========== V2 包元信息（适配命名+增强可读性） ==========
define Package/$(PKG_NAME)
	SECTION:=net               # 包分类：网络类
	CATEGORY:=Network          # LuCI 后台显示分类：Network
	TITLE:=VNT2 Client         # 包标题（明确标识 V2 客户端）
	SUBMENU:=VPN               # 子分类：VPN（可选，更易在后台查找）
	# 依赖：① 指定支持的架构 ② 必须依赖 tun 内核模块（VPN 隧道核心）
	DEPENDS:=@(i386||x86_64||arm||aarch64||mipsel||mips) +kmod-tun
	URL:=https://github.com/vnt-dev/vnt  # 保持原源码地址，有 V2 源码可修改
endef

# ========== V2 包描述（适配中文+V2 标识） ==========
define Package/$(PKG_NAME)/description
  V2版本 简便高效的异地组网、内网穿透工具（客户端）
  VNT2 Client - Efficient VPN for LAN penetration and remote networking
endef

# ========== 构建准备：下载预编译包+重命名（适配 V2） ==========
define Build/Prepare
	# 确保编译目录存在（防止解压失败）
	mkdir -p $(PKG_BUILD_DIR)
	# 检查预编译包是否已下载，未下载则从官方仓库获取（和 V1 下载逻辑一致）
	[ ! -f $(PKG_BUILD_DIR)/$(PKG_NAME)-$(APP_ARCH)-$(PKG_VERSION).tar.gz ] && \
		wget https://github.com/vnt-dev/vnt/releases/download/v$(PKG_VERSION)/vnt-$(APP_ARCH)-v$(PKG_VERSION).tar.gz -O $(PKG_BUILD_DIR)/$(PKG_NAME)-$(APP_ARCH)-$(PKG_VERSION).tar.gz
	# 解压预编译包到编译目录
	tar -xzvf $(PKG_BUILD_DIR)/$(PKG_NAME)-$(APP_ARCH)-$(PKG_VERSION).tar.gz -C $(PKG_BUILD_DIR)
	# 重命名二进制文件为 vnt2-cli（核心：V2 命名隔离）
	mv $(PKG_BUILD_DIR)/vnt-cli $(PKG_BUILD_DIR)/vnt2-cli || true
endef

# ========== 编译阶段：空实现（预编译包无需源码编译） ==========
define Build/Compile
endef

# ========== 安装阶段：部署 V2 客户端到系统 ==========
define Package/$(PKG_NAME)/install
	# 创建目标系统的 /usr/bin 目录（确保目录存在）
	$(INSTALL_DIR) $(1)/usr/bin
	# 安装 V2 客户端二进制文件（vnt2-cli）
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/vnt2-cli $(1)/usr/bin/vnt2-cli
	# 可选：创建软链接兼容 V1 命令（如需让旧脚本/配置兼容 V2，取消注释）
	# ln -s /usr/bin/vnt2-cli $(1)/usr/bin/vnt-cli || true
endef

# ========== 注册包编译目标（OpenWRT 必须） ==========
$(eval $(call BuildPackage,$(PKG_NAME)))
