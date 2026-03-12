# ============================================================
# CB-Shield LuCI 主题包 Makefile
# ============================================================

include $(TOPDIR)/rules.mk

LUCI_TITLE:=CB-Shield KJWS Theme
LUCI_DEPENDS:=+luci-base
LUCI_DESCRIPTION:=CB-Shield 跨境电商定制 LuCI 主题 (KJWS)

PKG_LICENSE:=MIT

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildance
$(eval $(call BuildPackage,luci-theme-cbshield))
