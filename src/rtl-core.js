;(function () {
    'use strict';

    if (typeof document === 'undefined') return;
    if (window.__adir_rtl_loaded__) return;
    window.__adir_rtl_loaded__ = true;

    // ─── Selectors ───────────────────────────────────────────────────────────
    const SEL = {
        message:  '.font-claude-message, .font-claude-response-body, .standard-markdown',
        input:    '[data-testid="chat-input"], [contenteditable="true"]',
        block:    'pre, code, .code-block__code',
        inline:   'p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th',
        lists:    'ol, ul',
    };

    // Unicode ranges: Hebrew, Arabic, Arabic Supplement, Arabic Extended
    const RTL_RANGES = [
        [0x0590, 0x05FF], // Hebrew
        [0x0600, 0x06FF], // Arabic
        [0x0750, 0x077F], // Arabic Supplement
        [0x08A0, 0x08FF], // Arabic Extended-A
        [0xFB1D, 0xFDFF], // Hebrew / Arabic Presentation Forms
        [0xFE70, 0xFEFF], // Arabic Presentation Forms-B
    ];

    function isRTL(ch) {
        const c = ch.charCodeAt(0);
        return RTL_RANGES.some(([lo, hi]) => c >= lo && c <= hi);
    }

    /**
     * Smarter RTL detection:
     * - Counts strong RTL vs LTR characters
     * - Returns true if RTL chars dominate OR if the first strong char is RTL
     *   AND RTL chars make up at least 20% of all letter characters.
     */
    function shouldRTL(text) {
        if (!text || !text.trim()) return false;
        let rtl = 0, ltr = 0, firstStrong = null;

        for (const ch of text.trim()) {
            if (isRTL(ch)) {
                rtl++;
                if (firstStrong === null) firstStrong = 'rtl';
            } else if (/\p{L}/u.test(ch)) {
                ltr++;
                if (firstStrong === null) firstStrong = 'ltr';
            }
        }

        if (firstStrong === null) return false;
        const total = rtl + ltr;
        if (total === 0) return false;
        if (firstStrong === 'rtl') return (rtl / total) >= 0.2;
        return (rtl / total) >= 0.6; // majority RTL even if starts LTR
    }

    // ─── Styling helpers ──────────────────────────────────────────────────────
    function setRTL(el) {
        el.style.direction   = 'rtl';
        el.style.textAlign   = 'right';
        el.style.unicodeBidi = 'plaintext';
    }

    function clearDir(el) {
        el.style.direction   = '';
        el.style.textAlign   = '';
        el.style.unicodeBidi = '';
    }

    function lockLTR(el) {
        el.style.direction   = 'ltr';
        el.style.textAlign   = 'left';
        el.style.unicodeBidi = 'embed';
    }

    // ─── Global style injection ───────────────────────────────────────────────
    function injectBaseStyles() {
        if (document.getElementById('adir-rtl-styles')) return;
        const s = document.createElement('style');
        s.id = 'adir-rtl-styles';
        s.textContent = `
            p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th {
                unicode-bidi: plaintext;
                direction: auto;
            }
            pre, code, .code-block__code {
                direction: ltr !important;
                text-align: left !important;
                unicode-bidi: embed !important;
            }
        `;
        document.head.appendChild(s);
    }

    // ─── Per-element processing ───────────────────────────────────────────────
    function processCodeBlocks(root) {
        root.querySelectorAll(SEL.block).forEach(lockLTR);
    }

    function processInlineElements(root) {
        root.querySelectorAll(SEL.inline).forEach(el => {
            if (el.closest(SEL.input) || el.closest(SEL.block)) return;
            shouldRTL(el.textContent) ? setRTL(el) : clearDir(el);
            if (el.tagName === 'LI' && el.style.direction === 'rtl') {
                el.style.listStylePosition = 'inside';
                el.style.paddingRight = '0.25rem';
            }
        });
    }

    function processLists(root) {
        root.querySelectorAll(SEL.lists).forEach(el => {
            if (el.closest(SEL.input) || el.closest(SEL.block)) return;
            if (shouldRTL(el.textContent)) {
                el.style.direction    = 'rtl';
                el.style.paddingRight = '1.5rem';
                el.style.paddingLeft  = '0';
            } else {
                el.style.direction    = '';
                el.style.paddingRight = '';
                el.style.paddingLeft  = '';
            }
        });
    }

    function processInput() {
        document.querySelectorAll(SEL.input).forEach(el => {
            const text = el.textContent || el.innerText || el.value || '';
            if (shouldRTL(text)) {
                el.style.direction    = 'rtl';
                el.style.textAlign    = 'right';
                el.style.paddingRight = '1.5rem';
            } else {
                el.style.direction    = 'ltr';
                el.style.textAlign    = 'left';
                el.style.paddingRight = '';
            }
        });
    }

    function processAll() {
        document.querySelectorAll(SEL.message).forEach(root => {
            if (root.closest(SEL.input)) return;
            processInlineElements(root);
            processLists(root);
            processCodeBlocks(root);
        });
        processInput();
        // Catch any stray code blocks outside message containers
        processCodeBlocks(document.body);
    }

    // ─── Input direction listener ─────────────────────────────────────────────
    function onInput(e) {
        const t = e.target;
        if (!t) return;
        const isEditable = t.tagName === 'TEXTAREA' || t.tagName === 'INPUT' || t.isContentEditable;
        if (!isEditable) return;
        const text = t.value || t.textContent || t.innerText || '';
        if (shouldRTL(text)) {
            t.style.direction    = 'rtl';
            t.style.textAlign    = 'right';
            t.style.paddingRight = '1.5rem';
        } else {
            t.style.direction    = 'ltr';
            t.style.textAlign    = 'left';
            t.style.paddingRight = '';
        }
    }

    // ─── MutationObserver — react to new messages ─────────────────────────────
    let _debounce = null;
    const observer = new MutationObserver(mutations => {
        const relevant = mutations.some(m => m.addedNodes.length > 0 || m.type === 'characterData');
        if (!relevant) return;
        clearTimeout(_debounce);
        _debounce = setTimeout(processAll, 60);
    });

    // ─── Boot ─────────────────────────────────────────────────────────────────
    function boot() {
        injectBaseStyles();
        processAll();
        document.addEventListener('input', onInput, true);
        observer.observe(document.body, {
            childList:     true,
            subtree:       true,
            characterData: true,
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot);
    } else {
        boot();
    }

})();
