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
