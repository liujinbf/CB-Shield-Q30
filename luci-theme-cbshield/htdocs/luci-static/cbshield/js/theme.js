/**
 * CB-Shield theme helpers
 */
(function() {
    "use strict";

    function initTheme() {
        highlightCurrentNav();
        initMobileMenu();
    }

    function highlightCurrentNav() {
        var currentPath = window.location.pathname;
        var navLinks = document.querySelectorAll(".navbar a, #mainmenu a, #modemenu a");

        for (var i = 0; i < navLinks.length; i++) {
            var link = navLinks[i];
            link.classList.remove("active");
            var href = link.getAttribute("href");
            if (href && href !== "/" && currentPath.indexOf(href) !== -1) {
                link.classList.add("active");
            }
        }
    }

    function initMobileMenu() {
        var header = document.querySelector("header, .header, #header");
        var nav = document.querySelector(".navbar, #mainmenu, #modemenu");
        if (!header || !nav) return;
        if (document.getElementById("cb-menu-toggle")) return;

        var toggle = document.createElement("button");
        toggle.id = "cb-menu-toggle";
        toggle.type = "button";
        toggle.textContent = "菜单";
        toggle.style.cssText = "display:none;margin-left:8px;background:#0d5fd4;color:#fff;border:0;border-radius:6px;padding:4px 10px;cursor:pointer;";

        toggle.addEventListener("click", function() {
            nav.classList.toggle("open");
        });
        header.appendChild(toggle);

        function checkMobile() {
            if (window.innerWidth <= 640) {
                toggle.style.display = "inline-block";
            } else {
                toggle.style.display = "none";
                nav.classList.remove("open");
            }
        }

        window.addEventListener("resize", checkMobile);
        checkMobile();
    }

    window.CBShieldNotify = {
        show: function(message, type, duration) {
            type = type || "info";
            duration = duration || 4000;

            var container = document.getElementById("cb-notifications");
            if (!container) {
                container = document.createElement("div");
                container.id = "cb-notifications";
                container.style.cssText = "position:fixed;top:72px;right:18px;z-index:9999;width:320px;";
                document.body.appendChild(container);
            }

            var colors = {
                success: "#27AE60",
                error: "#E74C3C",
                warning: "#F39C12",
                info: "#3498DB"
            };

            var toast = document.createElement("div");
            toast.style.cssText =
                "background:#fff;border-radius:8px;padding:10px 12px;margin-bottom:8px;" +
                "border-left:4px solid " + (colors[type] || colors.info) + ";" +
                "box-shadow:0 6px 20px rgba(0,0,0,.16);font-size:13px;transform:translateX(120%);transition:transform .25s ease;";
            toast.textContent = message;
            container.appendChild(toast);

            setTimeout(function() {
                toast.style.transform = "translateX(0)";
            }, 30);

            setTimeout(function() {
                toast.style.transform = "translateX(120%)";
                setTimeout(function() {
                    if (toast.parentNode) toast.parentNode.removeChild(toast);
                }, 250);
            }, duration);
        }
    };

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", initTheme);
    } else {
        initTheme();
    }
})();
