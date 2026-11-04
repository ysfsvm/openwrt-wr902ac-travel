include $(TOPDIR)/rules.mk

PKG_NAME:=modeswitch
PKG_VERSION:=2.3.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=retake <ysfss@protonmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/modeswitch
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Per-position config profiles for the hardware mode switch
  DEPENDS:=+slide-switch +jsonfilter
  PKGARCH:=all
endef

define Package/modeswitch/description
 Gives every position of a hardware mode switch its own network, wireless,
 firewall and DHCP profile. The running config is saved into the active
 position's profile on every change; other positions' profiles can be edited
 directly. Managed with modectl and luci-app-modeswitch.
endef

define Package/modeswitch/conffiles
/etc/config/modeswitch
/etc/modeswitch/defaults/ap.sh
/etc/modeswitch/defaults/share-eth.sh
/etc/modeswitch/defaults/share-hotspot.sh
endef

define Build/Compile
endef

define Package/modeswitch/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/share/modeswitch $(1)/etc/config \
		$(1)/etc/modeswitch/defaults $(1)/etc/hotplug.d/button $(1)/lib/upgrade/keep.d \
		$(1)/etc/init.d
	$(INSTALL_BIN) ./files/modectl $(1)/usr/sbin/modectl
	$(INSTALL_DATA) ./files/lib.sh $(1)/usr/share/modeswitch/lib.sh
	$(INSTALL_CONF) ./files/modeswitch.config $(1)/etc/config/modeswitch
	$(INSTALL_BIN) ./files/modeswitch.init $(1)/etc/init.d/modeswitch
	$(INSTALL_DATA) ./files/defaults/ap.sh ./files/defaults/share-eth.sh ./files/defaults/share-hotspot.sh \
		$(1)/etc/modeswitch/defaults/
	$(INSTALL_DATA) ./files/60-modeswitch $(1)/etc/hotplug.d/button/60-modeswitch
	$(INSTALL_DATA) ./files/modeswitch.keep $(1)/lib/upgrade/keep.d/modeswitch
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/modeswitch.uci-defaults $(1)/etc/uci-defaults/80-modeswitch-2.3.0
endef

$(eval $(call BuildPackage,modeswitch))
