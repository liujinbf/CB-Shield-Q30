include $(TOPDIR)/rules.mk

PKG_NAME:=cb-riskcontrol
PKG_VERSION:=1.0.1
PKG_RELEASE:=1

PKG_MAINTAINER:=KJWS <kjws@cbshield.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/cb-riskcontrol
  SECTION:=net
  CATEGORY:=Network
  TITLE:=CB-Shield IP Risk Control
  DEPENDS:=+curl +ipset +iptables +jsonfilter +uhttpd
  PKGARCH:=all
endef

define Package/cb-riskcontrol/description
  CB-Shield IP 风控服务，支持风险检测、策略动作和本地落地页服务。
endef

define Package/cb-riskcontrol/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/cb-riskcontrol.sh $(1)/usr/bin/cb-riskcontrol

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/cb-riskcontrol.init $(1)/etc/init.d/cb-riskcontrol
	$(INSTALL_BIN) ./files/cb-portal.init $(1)/etc/init.d/cb-portal

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/cb-riskcontrol.conf $(1)/etc/config/cb-riskcontrol
	$(INSTALL_CONF) ./files/cb-portal.conf $(1)/etc/config/cb-portal

	$(INSTALL_DIR) $(1)/www/cb-portal
	$(INSTALL_DATA) ./files/cb-portal.html $(1)/www/cb-portal/index.html
endef

define Package/cb-riskcontrol/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/cb-riskcontrol enable
	/etc/init.d/cb-portal enable
}
endef

$(eval $(call BuildPackage,cb-riskcontrol))
