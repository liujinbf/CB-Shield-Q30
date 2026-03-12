/**
 * CB-Shield Theme JS
 * 主题通用交互：导航高亮、侧边栏、移动端菜单、通知
 */
(function() {
    'use strict';

    /**
     * 初始化主题
     */
    function initTheme() {
        highlightCurrentNav();
        initMobileMenu();
        initSidebarCollapse();
        addBrandLogo();
    }

    /**
     * 高亮当前导航项
     */
    function highlightCurrentNav() {
        var currentPath = window.location.pathname;
        var navLinks = document.querySelectorAll('.navbar a, #mainnav a, .mainnavigation a');

        for (var i = 0; i < navLinks.length; i++) {
            var link = navLinks[i];
            link.classList.remove('active');

            var href = link.getAttribute('href');
            if (href && currentPath.indexOf(href) !== -1 && href !== '/') {
                link.classList.add('active');
            }
        }
    }

    /**
     * 移动端菜单切换
     */
    function initMobileMenu() {
        // 创建菜单切换按钮
        var header = document.querySelector('header, .header, #header');
        var nav = document.querySelector('.navbar, #mainnav, .mainnavigation');

        if (!header || !nav) return;

        // 检查是否已存在
        if (document.getElementById('cb-menu-toggle')) return;

        var toggle = document.createElement('button');
        toggle.id = 'cb-menu-toggle';
        toggle.innerHTML = '☰';
        toggle.style.cssText = 'display:none;background:none;border:none;color:white;font-size:24px;cursor:pointer;padding:4px 8px;';

        toggle.addEventListener('click', function() {
            nav.classList.toggle('open');
        });

        header.appendChild(toggle);

        // 响应式显示/隐藏
        function checkMobile() {
            if (window.innerWidth <= 640) {
                toggle.style.display = 'block';
            } else {
                toggle.style.display = 'none';
                nav.classList.remove('open');
            }
        }

        window.addEventListener('resize', checkMobile);
        checkMobile();
    }

    /**
     * 侧边栏折叠功能
     */
    function initSidebarCollapse() {
        var nav = document.querySelector('.navbar, #mainnav, .mainnavigation');
        if (!nav) return;

        // 子菜单折叠
        var parentLinks = nav.querySelectorAll('a[data-has-children]');
        for (var i = 0; i < parentLinks.length; i++) {
            parentLinks[i].addEventListener('click', function(e) {
                var submenu = this.nextElementSibling;
                if (submenu && submenu.tagName === 'UL') {
                    e.preventDefault();
                    submenu.style.display = submenu.style.display === 'none' ? 'block' : 'none';
                    this.classList.toggle('expanded');
                }
            });
        }
    }

    /**
     * 添加品牌 Logo
     */
    function addBrandLogo() {
        var header = document.querySelector('header, .header, #header');
        if (!header) return;

        // 如果还没有品牌 logo
        var logo = header.querySelector('.kjws-logo, .brand');
        if (!logo) {
            logo = document.createElement('div');
            logo.className = 'kjws-logo';
            logo.textContent = 'CB-Shield-Q30';
            header.insertBefore(logo, header.firstChild);
        }
    }

    /**
     * 通知消息组件
     */
    window.CBShieldNotify = {
        show: function(message, type, duration) {
            type = type || 'info';
            duration = duration || 5000;

            var container = document.getElementById('cb-notifications');
            if (!container) {
                container = document.createElement('div');
                container.id = 'cb-notifications';
                container.style.cssText = 'position:fixed;top:70px;right:20px;z-index:10000;width:320px;';
                document.body.appendChild(container);
            }

            var icons = { success: '✅', error: '❌', warning: '⚠️', info: 'ℹ️' };
            var colors = { success: '#27AE60', error: '#E74C3C', warning: '#F39C12', info: '#3498DB' };

            var toast = document.createElement('div');
            toast.style.cssText = 'background:white;border-radius:8px;padding:12px 16px;margin-bottom:8px;' +
                'box-shadow:0 4px 16px rgba(0,0,0,0.15);border-left:4px solid ' + colors[type] + ';' +
                'transform:translateX(120%);transition:transform 0.3s ease;font-size:14px;';
            toast.innerHTML = '<span style="margin-right:8px;">' + (icons[type] || '') + '</span>' + message;

            container.appendChild(toast);

            // 动画进入
            setTimeout(function() { toast.style.transform = 'translateX(0)'; }, 50);

            // 自动移除
            setTimeout(function() {
                toast.style.transform = 'translateX(120%)';
                setTimeout(function() {
                    if (toast.parentNode) toast.parentNode.removeChild(toast);
                }, 300);
            }, duration);
        }
    };

    // DOM Ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initTheme);
    } else {
        initTheme();
    }
})();
