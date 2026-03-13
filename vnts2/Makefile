include $(TOPDIR)/rules.mk

PKG_NAME:=vnts2
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

# V2 服务端源码地址（vnts是独立仓库）
PKG_SOURCE_URL:=https://github.com/vnt-dev/vnts.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=main  # vnts的V2版本在main分支
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION)-$(PKG_SOURCE_VERSION).tar.gz

# 依赖Rust编译环境
PKG_BUILD_DEPENDS:=rust/host cargo/host

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# 配置Rust交叉编译环境
define Build/Configure
	# 设置Rust目标架构
	if [ "$(ARCH)" = "x86_64" ]; then
		export CARGO_TARGET=x86_64-unknown-linux-musl;
	elif [ "$(ARCH)" = "aarch64" ]; then
		export CARGO_TARGET=aarch64-unknown-linux-musl;
	elif [ "$(ARCH)" = "armv7" ]; then
		export CARGO_TARGET=armv7-unknown-linux-musleabihf;
	elif [ "$(ARCH)" = "mipsel" ]; then
		export CARGO_TARGET=mipsel-unknown-linux-musl;
	fi
	
	# 复制交叉编译配置
	mkdir -p $(PKG_BUILD_DIR)/.cargo
	cat > $(PKG_BUILD_DIR)/.cargo/config << EOF
[build]
target = "$${CARGO_TARGET}"

[target.$${CARGO_TARGET}]
linker = "$(TARGET_CC)"
EOF
endef

# 编译V2服务端
define Build/Compile
	cd $(PKG_BUILD_DIR) && \
		export CC=$(TARGET_CC) CXX=$(TARGET_CXX) && \
		cargo build --release --target=$${CARGO_TARGET};
	
	# 复制编译产物
	cp $(PKG_BUILD_DIR)/target/$${CARGO_TARGET}/release/vnts $(PKG_BUILD_DIR)/vnts2
endef

define Package/vnts2
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=VNT2 Server (vnts2)
  DEPENDS:=+libc +libgcc
  URL:=https://github.com/vnt-dev/vnts
endef

define Package/vnts2/description
  VNT2 server (source compiled from main branch) for OpenWrt 24.10
endef

define Package/vnts2/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/vnts2 $(1)/usr/bin/vnts2
endef

$(eval $(call BuildPackage,vnts2))
