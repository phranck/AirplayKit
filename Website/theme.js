//
//  theme.js
//  The theme switch.
//
//  The page follows the system by default, and this only overrides it once
//  somebody asks. What it writes is a data attribute; the stylesheet holds both
//  palettes in one declaration each, so nothing here knows a colour.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

(function setUpThemeToggle() {
    const toggle = document.getElementById("theme-toggle");
    if (!toggle) return;

    const root = document.documentElement;
    const systemPrefersDark = window.matchMedia("(prefers-color-scheme: dark)");

    /** Whether what is on screen right now is the dark palette. */
    function isDark() {
        const chosen = root.dataset.theme;
        return chosen ? chosen === "dark" : systemPrefersDark.matches;
    }

    function reflectState() {
        toggle.setAttribute("aria-pressed", String(isDark()));
        toggle.setAttribute("aria-label", isDark() ? "Switch to the light theme" : "Switch to the dark theme");
    }

    toggle.addEventListener("click", function chooseTheOtherTheme() {
        const wanted = isDark() ? "light" : "dark";
        root.dataset.theme = wanted;

        try {
            localStorage.setItem("theme", wanted);
        } catch (error) {
            // Private browsing refuses storage. The choice then lasts for this
            // page only, which is better than refusing to switch at all.
        }

        reflectState();
    });

    // Somebody who never pressed the switch is following the system, so the
    // control follows it too when the system changes under them.
    systemPrefersDark.addEventListener("change", reflectState);

    reflectState();
})();
