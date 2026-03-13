include $(TOPDIR)/rules.mk

PKG_NAME:=vnt2
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

# V2 分支源码地址
PKG_SOURCE_URL:=https://github.com/vnt-dev/vnt.git
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=v2  # 对应V2分支
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

# 编译V2客户端
define Build/Compile
	cd $(PKG_BUILD_DIR) && \
		export CC=$(TARGET_CC) CXX=$(TARGET_CXX) && \
		cargo build --release --target=$${CARGO_TARGET} --no-default-features --features cli;
	
	# 复制编译产物
	cp $(PKG_BUILD_DIR)/target/$${CARGO_TARGET}/release/vnt-cli $(PKG_BUILD_DIR)/vnt2-cli
endef

define Package/vnt2
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=VNT2 Client (vnt2-cli)
  DEPENDS:=+kmod-tun +libc +libgcc
  URL:=https://github.com/vnt-dev/vnt/tree/v2
endef

define Package/vnt2/description
  VNT2 client (source compiled from v2 branch) for OpenWrt 24.10
endef

define Package/vnt2/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/vnt2-cli $(1)/usr/bin/vnt2-cli
endef

$(eval $(call BuildPackage,vnt2))
