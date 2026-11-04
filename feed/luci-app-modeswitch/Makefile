include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-modeswitch
PKG_VERSION:=2.3.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=retake <ysfss@protonmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-modeswitch
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI page for the hardware mode switch (modeswitch)
  DEPENDS:=+modeswitch +luci-base
  PKGARCH:=all
endef

define Build/Compile
endef

define Package/luci-app-modeswitch/install
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view $(1)/www/luci-static/resources/preload \
		$(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/modeswitch.js $(1)/www/luci-static/resources/view/modeswitch.js
	$(INSTALL_DATA) ./files/preload/modeswitch.js $(1)/www/luci-static/resources/preload/modeswitch.js
	$(INSTALL_DATA) ./files/menu.json $(1)/usr/share/luci/menu.d/luci-app-modeswitch.json
	$(INSTALL_DATA) ./files/acl.json $(1)/usr/share/rpcd/acl.d/luci-app-modeswitch.json
endef

define Package/luci-app-modeswitch/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || { rm -f /tmp/luci-indexcache*; /etc/init.d/rpcd reload; }
exit 0
endef

$(eval $(call BuildPackage,luci-app-modeswitch))
