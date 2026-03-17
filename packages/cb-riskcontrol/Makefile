include $(TOPDIR)/rules.mk

PKG_NAME:=cb-riskcontrol
PKG_VERSION:=1.2.0
PKG_RELEASE:=1

PKG_MAINTAINER:=KJWS <kjws@cbshield.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/cb-riskcontrol
  SECTION:=net
  CATEGORY:=Network
  TITLE:=CB-Shield Ops Stack
  DEPENDS:=+curl +ipset +iptables +jsonfilter +uhttpd +coreutils +coreutils-nohup
  PKGARCH:=all
endef

define Package/cb-riskcontrol/description
  CB-Shield 运维能力集合，包含风控、健康自检、HA、DNS 防泄漏、策略编排、安全升级与首次向导。
endef

define Package/cb-riskcontrol/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/cb-riskcontrol.sh $(1)/usr/bin/cb-riskcontrol
	$(INSTALL_BIN) ./files/cb-eventlog.sh $(1)/usr/bin/cb-eventlog
	$(INSTALL_BIN) ./files/cb-healthcheck.sh $(1)/usr/bin/cb-healthcheck
	$(INSTALL_BIN) ./files/cb-ha-monitor.sh $(1)/usr/bin/cb-ha-monitor
	$(INSTALL_BIN) ./files/cb-dns-guard.sh $(1)/usr/bin/cb-dns-guard
	$(INSTALL_BIN) ./files/cb-policy-engine.sh $(1)/usr/bin/cb-policy-engine
	$(INSTALL_BIN) ./files/cb-safe-upgrade.sh $(1)/usr/bin/cb-safe-upgrade
	$(INSTALL_BIN) ./files/cb-wizard.sh $(1)/usr/bin/cb-wizard

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/cb-riskcontrol.init $(1)/etc/init.d/cb-riskcontrol
	$(INSTALL_BIN) ./files/cb-portal.init $(1)/etc/init.d/cb-portal
	$(INSTALL_BIN) ./files/cb-healthcheck.init $(1)/etc/init.d/cb-healthcheck
	$(INSTALL_BIN) ./files/cb-ha-monitor.init $(1)/etc/init.d/cb-ha-monitor
	$(INSTALL_BIN) ./files/cb-dns-guard.init $(1)/etc/init.d/cb-dns-guard
	$(INSTALL_BIN) ./files/cb-policy-engine.init $(1)/etc/init.d/cb-policy-engine

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/cb-riskcontrol.conf $(1)/etc/config/cb-riskcontrol
	$(INSTALL_CONF) ./files/cb-portal.conf $(1)/etc/config/cb-portal
	$(INSTALL_CONF) ./files/cb-health.conf $(1)/etc/config/cb-health
	$(INSTALL_CONF) ./files/cb-ha.conf $(1)/etc/config/cb-ha
	$(INSTALL_CONF) ./files/cb-dns-guard.conf $(1)/etc/config/cb-dns-guard
	$(INSTALL_CONF) ./files/cb-policy.conf $(1)/etc/config/cb-policy
	$(INSTALL_CONF) ./files/cb-wizard.conf $(1)/etc/config/cb-wizard

	$(INSTALL_DIR) $(1)/etc/cbshield
	$(INSTALL_DATA) ./files/wizard_required $(1)/etc/cbshield/wizard_required

	$(INSTALL_DIR) $(1)/www/cb-portal
	$(INSTALL_DATA) ./files/cb-portal.html $(1)/www/cb-portal/index.html
endef

define Package/cb-riskcontrol/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/cb-riskcontrol enable
	/etc/init.d/cb-portal enable
	/etc/init.d/cb-healthcheck enable
	/etc/init.d/cb-ha-monitor enable
	/etc/init.d/cb-dns-guard enable
	/etc/init.d/cb-policy-engine enable
}
endef

define Build/Compile
endef

$(eval $(call BuildPackage,cb-riskcontrol))
