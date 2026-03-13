include $(TOPDIR)/rules.mk

PKG_NAME:=vnts2
PKG_VERSION:=1.2.12
PKG_RELEASE:=1

# 架构适配
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
	PKG_VERSION:=1.2.11
	APP_ARCH:=i686-unknown-linux-musl
endif
ifeq ($(ARCH),x86_64)
	APP_ARCH:=x86_64-unknown-linux-musl
endif

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/vnts2
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=VNT2 Server (vnts2)
  URL:=https://github.com/vnt-dev/vnts
endef

define Package/vnts2/description
  VNT2 server binary (vnts2) for OpenWrt
endef

# ✅ 核心修复：补全 if/fi 语法，每一行用 \ 续行
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	if [ "$(ARCH)" = "i386" ]; then \
		wget --no-check-certificate https://github.com/vnt-dev/vnts/releases/download/$(PKG_VERSION)/vnts-$(APP_ARCH)-$(PKG_VERSION).tar.gz -O $(PKG_BUILD_DIR)/vnts2.tar.gz; \
	else \
		wget --no-check-certificate https://github.com/vnt-dev/vnts/releases/download/v$(PKG_VERSION)/vnts-$(APP_ARCH)-v$(PKG_VERSION).tar.gz -O $(PKG_BUILD_DIR)/vnts2.tar.gz; \
	fi
	tar -xzf $(PKG_BUILD_DIR)/vnts2.tar.gz -C $(PKG_BUILD_DIR)
	mv $(PKG_BUILD_DIR)/vnts $(PKG_BUILD_DIR)/vnts2 || true
endef

define Build/Compile
endef

define Package/vnts2/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/vnts2 $(1)/usr/bin/vnts2
endef

$(eval $(call BuildPackage,vnts2))
