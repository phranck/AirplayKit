//
//  copy.js
//  The copy button on each code panel.
//
//  What it copies is the text of the panel's own code, so the markup that
//  colours it never reaches the clipboard.
//
//  Copyright © 2026 cocoa:naut. All rights reserved.
//

(function setUpCopyButtons() {
    /** How long the tick stays before the button goes back to offering the copy. */
    const confirmationDuration = 1600;

    for (const button of document.querySelectorAll(".copy")) {
        const panel = button.closest(".panel");
        if (!panel) continue;

        // A panel may hold several versions of the same thing, and what gets
        // copied is the one on show.
        const visibleCode = () => panel.querySelector("pre:not([hidden])");
        if (!visibleCode()) continue;

        let goingBack = 0;

        button.addEventListener("click", async function copyThePanel() {
            try {
                await navigator.clipboard.writeText(visibleCode().innerText);
            } catch (error) {
                // A browser that refuses the clipboard, usually because the page
                // is not on a secure origin. Saying so beats a button that does
                // nothing and looks as though it worked.
                button.dataset.state = "refused";
                window.clearTimeout(goingBack);
                goingBack = window.setTimeout(() => delete button.dataset.state, confirmationDuration);
                return;
            }

            button.dataset.state = "copied";
            window.clearTimeout(goingBack);
            goingBack = window.setTimeout(() => delete button.dataset.state, confirmationDuration);
        });
    }
})();
