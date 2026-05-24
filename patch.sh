#!/usr/bin/env bash
# =============================================================================
# claude-rtl — macOS
# RTL support for Claude Desktop: Hebrew & Arabic text direction detection.
#
# Author : adirbenmeir — https://github.com/adirbenmeir/claude-rtl
# Version: 1.0.0
# =============================================================================

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
C_BLUE='\033[0;34m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'; C_GRAY='\033[0;90m'; C_RESET='\033[0m'

log()     { echo -e "  ${C_BLUE}→${C_RESET} $1"; }
ok()      { echo -e "  ${C_GREEN}✓${C_RESET} $1"; }
warn()    { echo -e "  ${C_YELLOW}⚠${C_RESET}  $1"; }
fail()    { echo -e "  ${C_RED}✗${C_RESET} $1"; exit 1; }
section() { echo -e "\n${C_BLUE}$1${C_RESET}"; }

# ─── Paths ────────────────────────────────────────────────────────────────────
CLAUDE_APP="/Applications/Claude.app"
RESOURCES="$CLAUDE_APP/Contents/Resources"
ASAR_PATH="$RESOURCES/app.asar"
WORK_DIR="/tmp/adir_rtl_$$"
PACKED="/tmp/adir_rtl_packed_$$.asar"

# ─── RTL JavaScript payload ───────────────────────────────────────────────────
# Identical logic to the Windows version — same injected fingerprint.
RTL_JS=';(function () {
    '"'"'use strict'"'"';
    if (typeof document === '"'"'undefined'"'"') return;
    if (window.__adir_rtl_loaded__) return;
    window.__adir_rtl_loaded__ = true;

    const SEL = {
        message: '"'"'.font-claude-message, .font-claude-response-body, .standard-markdown'"'"',
        input:   '"'"'[data-testid="chat-input"], [contenteditable="true"]'"'"',
        block:   '"'"'pre, code, .code-block__code'"'"',
        inline:  '"'"'p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th'"'"',
        lists:   '"'"'ol, ul'"'"',
    };

    const RTL_RANGES = [
        [0x0590, 0x05FF],[0x0600, 0x06FF],[0x0750, 0x077F],
        [0x08A0, 0x08FF],[0xFB1D, 0xFDFF],[0xFE70, 0xFEFF],
    ];

    function isRTL(ch) {
        const c = ch.charCodeAt(0);
        return RTL_RANGES.some(([lo, hi]) => c >= lo && c <= hi);
    }

    function shouldRTL(text) {
        if (!text || !text.trim()) return false;
        let rtl = 0, ltr = 0, firstStrong = null;
        for (const ch of text.trim()) {
            if (isRTL(ch)) { rtl++; if (firstStrong === null) firstStrong = '"'"'rtl'"'"'; }
            else if (/\p{L}/u.test(ch)) { ltr++; if (firstStrong === null) firstStrong = '"'"'ltr'"'"'; }
        }
        if (firstStrong === null) return false;
        const total = rtl + ltr;
        if (total === 0) return false;
        if (firstStrong === '"'"'rtl'"'"') return (rtl / total) >= 0.2;
        return (rtl / total) >= 0.6;
    }

    function setRTL(el)   { el.style.direction='"'"'rtl'"'"'; el.style.textAlign='"'"'right'"'"'; el.style.unicodeBidi='"'"'plaintext'"'"'; }
    function clearDir(el) { el.style.direction='"'"''"'"'; el.style.textAlign='"'"''"'"'; el.style.unicodeBidi='"'"''"'"'; }
    function lockLTR(el)  { el.style.direction='"'"'ltr'"'"'; el.style.textAlign='"'"'left'"'"'; el.style.unicodeBidi='"'"'embed'"'"'; }

    function injectBaseStyles() {
        if (document.getElementById('"'"'adir-rtl-styles'"'"')) return;
        const s = document.createElement('"'"'style'"'"');
        s.id = '"'"'adir-rtl-styles'"'"';
        s.textContent = '"'"'p,li,h1,h2,h3,h4,h5,h6,blockquote,td,th{unicode-bidi:plaintext;direction:auto}pre,code,.code-block__code{direction:ltr!important;text-align:left!important;unicode-bidi:embed!important}'"'"';
        document.head.appendChild(s);
    }

    function processCodeBlocks(root) { root.querySelectorAll(SEL.block).forEach(lockLTR); }

    function processInline(root) {
        root.querySelectorAll(SEL.inline).forEach(el => {
            if (el.closest(SEL.input) || el.closest(SEL.block)) return;
            shouldRTL(el.textContent) ? setRTL(el) : clearDir(el);
            if (el.tagName === '"'"'LI'"'"' && el.style.direction === '"'"'rtl'"'"') {
                el.style.listStylePosition = '"'"'inside'"'"';
                el.style.paddingRight = '"'"'0.25rem'"'"';
            }
        });
    }

    function processLists(root) {
        root.querySelectorAll(SEL.lists).forEach(el => {
            if (el.closest(SEL.input) || el.closest(SEL.block)) return;
            if (shouldRTL(el.textContent)) {
                el.style.direction='"'"'rtl'"'"'; el.style.paddingRight='"'"'1.5rem'"'"'; el.style.paddingLeft='"'"'0'"'"';
            } else {
                el.style.direction='"'"''"'"'; el.style.paddingRight='"'"''"'"'; el.style.paddingLeft='"'"''"'"';
            }
        });
    }

    function processInput() {
        document.querySelectorAll(SEL.input).forEach(el => {
            const text = el.textContent || el.innerText || el.value || '"'"''"'"';
            if (shouldRTL(text)) {
                el.style.direction='"'"'rtl'"'"'; el.style.textAlign='"'"'right'"'"'; el.style.paddingRight='"'"'1.5rem'"'"';
            } else {
                el.style.direction='"'"'ltr'"'"'; el.style.textAlign='"'"'left'"'"'; el.style.paddingRight='"'"''"'"';
            }
        });
    }

    function processAll() {
        document.querySelectorAll(SEL.message).forEach(root => {
            if (root.closest(SEL.input)) return;
            processInline(root);
            processLists(root);
            processCodeBlocks(root);
        });
        processInput();
        processCodeBlocks(document.body);
    }

    function onInput(e) {
        const t = e.target;
        if (!t) return;
        if (!(t.tagName==='"'"'TEXTAREA'"'"'||t.tagName==='"'"'INPUT'"'"'||t.isContentEditable)) return;
        const text = t.value||t.textContent||t.innerText||'"'"''"'"';
        if (shouldRTL(text)) { t.style.direction='"'"'rtl'"'"'; t.style.textAlign='"'"'right'"'"'; t.style.paddingRight='"'"'1.5rem'"'"'; }
        else { t.style.direction='"'"'ltr'"'"'; t.style.textAlign='"'"'left'"'"'; t.style.paddingRight='"'"''"'"'; }
    }

    let _d = null;
    const obs = new MutationObserver(muts => {
        if (!muts.some(m => m.addedNodes.length > 0 || m.type==='"'"'characterData'"'"')) return;
        clearTimeout(_d);
        _d = setTimeout(processAll, 60);
    });

    function boot() {
        injectBaseStyles();
        processAll();
        document.addEventListener('"'"'input'"'"', onInput, true);
        obs.observe(document.body, { childList:true, subtree:true, characterData:true });
    }

    document.readyState === '"'"'loading'"'"'
        ? document.addEventListener('"'"'DOMContentLoaded'"'"', boot)
        : boot();
})();'

# ─── Python: compute ASAR header SHA-256 ─────────────────────────────────────
PY_HASH='
import sys, struct, hashlib
with open(sys.argv[1], "rb") as f:
    f.seek(12)
    n = struct.unpack("<I", f.read(4))[0]
    data = f.read(n)
print(hashlib.sha256(data.decode("utf-8").encode("utf-8")).hexdigest())
'

# ─── Helpers ──────────────────────────────────────────────────────────────────
asar_hash() { python3 - "$1" <<< "$PY_HASH"; }

finder_copy() {
    # Uses Finder to copy files into protected app bundle directories
    local src="$1" dst_dir="$2" name="$3"
    osascript <<APPLE 2>/dev/null
tell application "Finder"
    try
        set ex to (POSIX file "${dst_dir}${name}") as alias
        delete ex
    end try
    set f to duplicate (POSIX file "${src}") to ((POSIX file "${dst_dir}") as alias)
    set name of f to "${name}"
end tell
APPLE
}

quit_claude() {
    section "Stopping Claude..."
    osascript -e 'tell application "Claude" to quit' 2>/dev/null || true
    sleep 1
    pkill -x "Claude" 2>/dev/null || true
    sleep 1
    ok "Claude stopped"
}

launch_claude() {
    section "Launching Claude..."
    open -a Claude 2>/dev/null && ok "Claude launched" || warn "Please open Claude manually"
}

check_deps() {
    section "Checking dependencies..."
    [[ -d "$CLAUDE_APP" ]] || fail "Claude Desktop not found at $CLAUDE_APP"
    [[ -f "$ASAR_PATH"  ]] || fail "app.asar not found — is Claude installed?"
    command -v node    >/dev/null 2>&1 || fail "Node.js required — https://nodejs.org"
    command -v python3 >/dev/null 2>&1 || fail "python3 required"
    # Install asar globally if missing (speeds up future runs)
    if ! command -v asar >/dev/null 2>&1; then
        log "Installing asar globally..."
        npm install -g asar >/dev/null 2>&1 && ok "asar installed" || fail "Could not install asar — run: npm install -g asar"
    else
        ok "asar already installed"
    fi
    ok "All dependencies found"
}

# ─── Install ──────────────────────────────────────────────────────────────────
do_install() {
    check_deps
    quit_claude

    # Extract
    section "Extracting app bundle..."
    rm -rf "$WORK_DIR"
    asar extract "$ASAR_PATH" "$WORK_DIR"
    ok "Extracted"

    # Inject RTL
    section "Injecting RTL script..."
    local count=0
    # Target only the 2 largest JS files (main renderer bundles)
    # Cuts injection time ~70% vs patching all files
    while IFS= read -r js; do
        grep -q "__adir_rtl_loaded__" "$js" 2>/dev/null && continue
        local tmp; tmp=$(mktemp)
        printf '%s\n' "$RTL_JS" > "$tmp"
        cat "$js" >> "$tmp"
        mv "$tmp" "$js"
        log "Patched: $(basename "$js")"
        ((count++))
    done < <(find "$WORK_DIR/.vite" -name "*.js" 2>/dev/null | xargs ls -S 2>/dev/null | head -2)

    [[ $count -gt 0 ]] && ok "Injected into $count file(s)" || warn "No files injected (already patched?)"

    # Repack
    section "Repacking bundle..."
    asar pack "$WORK_DIR" "$PACKED" --unpack "{*.node,spawn-helper}"
    rm -rf "$WORK_DIR"
    ok "Repacked ($(du -sh "$PACKED" | cut -f1))"

    # Hashes
    section "Computing integrity hashes..."
    local old_hash new_hash
    old_hash=$(asar_hash "$ASAR_PATH")
    new_hash=$(asar_hash "$PACKED")
    log "Old: $old_hash"
    log "New: $new_hash"

    # Install ASAR via Finder
    section "Installing patched bundle..."
    finder_copy "$PACKED" "$RESOURCES/" "app.asar"
    rm -f "$PACKED"
    [[ -f "$ASAR_PATH" ]] || fail "Failed to install app.asar — try running with sudo"
    ok "Bundle installed"

    # Update plists
    section "Updating integrity hashes in plists..."
    local tmp_dir; tmp_dir=$(mktemp -d)
    local updated=0

    while IFS= read -r -d '' plist; do
        grep -q "$old_hash" "$plist" 2>/dev/null || continue
        local tmp_file="$tmp_dir/$(basename "$(dirname "$plist")")_Info.plist"
        sed "s/$old_hash/$new_hash/g" "$plist" > "$tmp_file"
        finder_copy "$tmp_file" "$(dirname "$plist")/" "Info.plist"
        log "Updated: ${plist#"$CLAUDE_APP/"}"
        ((updated++))
    done < <(find "$CLAUDE_APP" -name "Info.plist" -print0)

    rm -rf "$tmp_dir"
    [[ $updated -gt 0 ]] && ok "Updated $updated plist(s)" || warn "No plists required updating"

    # Re-sign
    section "Re-signing app bundle..."
    find "$CLAUDE_APP" -type f \( -name "*.dylib" -o -perm +111 \) | while read -r f; do
        file "$f" 2>/dev/null | grep -q "Mach-O" && \
            codesign --sign - --force "$f" 2>/dev/null
    done

    find "$CLAUDE_APP" -name "*.framework" -o -name "*.app" | while read -r b; do
        codesign --sign - --force --deep "$b" 2>/dev/null || true
    done

    codesign --sign - --force --deep "$CLAUDE_APP" 2>/dev/null || true
    ok "App bundle re-signed (ad-hoc)"

    launch_claude

    echo ""
    echo -e "${C_GREEN}  RTL patch installed. Hebrew and Arabic now render correctly.${C_RESET}"
    echo -e "${C_GRAY}  Re-run this script after each Claude Desktop update.${C_RESET}"
    echo ""
}

# ─── Restore ──────────────────────────────────────────────────────────────────
do_restore() {
    echo ""
    warn "Automatic restore is not available on macOS."
    echo ""
    echo "  To restore Claude Desktop:"
    echo "  1. Download a fresh copy from https://claude.ai/download"
    echo "  2. Drag the new Claude.app to /Applications — overwrite when prompted"
    echo ""
}

# ─── Menu ─────────────────────────────────────────────────────────────────────
header() {
    clear
    echo ""
    echo -e "  ${C_BLUE}▌${C_RESET} Claude RTL — macOS"
    echo -e "  ${C_BLUE}▌${C_RESET} github.com/adirbenmeir/claude-rtl"
    echo -e "  ${C_GRAY}  ────────────────────────────────${C_RESET}"
    echo ""
}

header
echo "  1  Install RTL patch"
echo "  2  How to restore original"
echo "  3  Exit"
echo ""
read -rp "  → " CHOICE

case "$CHOICE" in
    1)
        echo ""
        read -rp "  This will briefly quit Claude Desktop. Continue? [y/N] " ok
        [[ "$ok" =~ ^[Yy]$ ]] || { echo "  Cancelled."; exit 0; }
        do_install
        ;;
    2) do_restore ;;
    3) exit 0 ;;
    *) fail "Invalid option" ;;
esac
