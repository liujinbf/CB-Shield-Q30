# ============================================================
# CB-Shield-Q30 风控包 Makefile
# ============================================================

include $(TOPDIR)/rules.mk

PKG_NAME:=cb-riskcontrol
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=KJWS <kjws@cbshield.com>
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/cb-riskcontrol
  SECTION:=net
  CATEGORY:=Network
  TITLE:=CB-Shield IP Risk Control
  DEPENDS:=+curl +ipset +iptables +jsonfilter
  PKGARCH:=all
endef

define Package/cb-riskcontrol/description
  IP 风控检测服务，用于检测代理/VPN IP，
  保障跨境电商账号安全。支持自动切换 IP 和断网防护。
endef

define Package/cb-riskcontrol/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/cb-riskcontrol.sh $(1)/usr/bin/cb-riskcontrol

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/cb-riskcontrol.init $(1)/etc/init.d/cb-riskcontrol

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/cb-riskcontrol.conf $(1)/etc/config/cb-riskcontrol

	# === 安装高级业务落地页 (V3.0) ===
	$(INSTALL_DIR) $(1)/www/cb-portal
	$(INSTALL_DATA) ./files/cb-portal.html $(1)/www/cb-portal/index.html

	$(INSTALL_DIR) $(1)/etc/config
	# 直接将独立的 uhttpd 配置文件追加到系统的 uhttpd 中，或者提供单独的启动脚本
	# 这里我们提供一个专属的 uhttpd 实例配置 cb-portal
	$(INSTALL_CONF) ./files/cb-portal.conf $(1)/etc/config/cb-portal
	
	# 加入开机自启脚本
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/cb-portal.init $(1)/etc/init.d/cb-portal

define Package/cb-riskcontrol/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/cb-riskcontrol enable
	/etc/init.d/cb-portal enable
}
endef

$(eval $(call BuildPackage,cb-riskcontrol))
