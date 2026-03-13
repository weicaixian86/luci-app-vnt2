include $(TOPDIR)/rules.mk

PKG_NAME:=vnt2
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

ifeq ($(ARCH),mipsel)
	APP_ARCH:=mipsel-unknown-linux-musl
endif
ifeq ($(ARCH),mips)
	APP_ARCH:=mips-unknown-linux-musl
endif
ifeq ($(ARCH),arm)
	APP_ARCH:=arm-unknown-linux-musleabi
endif
ifeq ($(ARCH),armv7)
	APP_ARCH:=armv7-unknown-linux-musleabi
endif
ifeq ($(ARCH),aarch64)
	APP_ARCH:=aarch64-unknown-linux-musl
endif
ifeq ($(ARCH),i386)
	APP_ARCH:=i686-unknown-linux-musl
endif
ifeq ($(ARCH),x86_64)
	APP_ARCH:=x86_64-unknown-linux-musl
endif

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/vnt2
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=VNT2 Client (vnt2-cli)
  DEPENDS:=@(i386||x86_64||arm||aarch64||mipsel||mips) +kmod-tun
  URL:=https://github.com/vnt-dev/vnt/tree/v2
endef

define Package/vnt2/description
  VNT2 client binary (vnt2-cli) for OpenWrt 24.10
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	wget https://github.com/vnt-dev/vnt/releases/download/v$(PKG_VERSION)/vnt-$(APP_ARCH)-v$(PKG_VERSION).tar.gz -O $(PKG_BUILD_DIR)/vnt2.tar.gz
	tar -xzf $(PKG_BUILD_DIR)/vnt2.tar.gz -C $(PKG_BUILD_DIR)
	mv $(PKG_BUILD_DIR)/vnt-cli $(PKG_BUILD_DIR)/vnt2-cli
endef

define Build/Compile
endef

define Package/vnt2/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/vnt2-cli $(1)/usr/bin/vnt2-cli
endef

$(eval $(call BuildPackage,vnt2))
