//
//  variants.js
//  The platform switch on a code panel.
//
//  A panel that carries more than one version of the same thing holds them all
//  and shows one. The buttons in its caption say which, and the panel keeps its
//  choice on its own element so two panels on a page do not fight over it.
//
//  Copyright © 2026 LAYERED. All rights reserved.
//

(function setUpVariantSwitches() {
    for (const panel of document.querySelectorAll(".panel[data-variant]")) {
        const buttons = panel.querySelectorAll(".variant");
        const blocks = panel.querySelectorAll("pre[data-variant]");

        function show(wanted) {
            panel.dataset.variant = wanted;

            for (const button of buttons) {
                button.setAttribute("aria-pressed", String(button.dataset.variant === wanted));
            }

            for (const block of blocks) {
                block.hidden = block.dataset.variant !== wanted;
            }
        }

        for (const button of buttons) {
            button.addEventListener("click", () => show(button.dataset.variant));
        }
    }
})();
