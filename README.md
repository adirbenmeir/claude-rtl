# claude-rtl

**RTL support for Claude Desktop — Hebrew & Arabic.**  
Works on both Windows and macOS.

---

## Windows

```powershell
irm https://raw.githubusercontent.com/adirbenmeir/claude-rtl/main/install.ps1 | iex
```

A UAC prompt will appear — click **Yes**.

**Requirements:** Windows 10/11 · [Node.js](https://nodejs.org) v16+

---

## macOS

```bash
curl -fsSL https://raw.githubusercontent.com/adirbenmeir/claude-rtl/main/patch.sh | bash
```

**Requirements:** macOS 12+ · [Node.js](https://nodejs.org) v16+ · `npm install -g asar`

---

## What it does

- Detects Hebrew and Arabic characters per element
- Right-aligns RTL paragraphs, headings, and list items
- Keeps code blocks and English text left-to-right
- Reacts in real time as Claude streams responses
- Works in Chat and Cowork modes

---

## After a Claude update

Claude Desktop updates overwrite the patched files. Re-run the install command above.

---

## Remove

**Windows:** Run the installer and choose option **2**.  
**macOS:** Download a fresh Claude from [claude.ai/download](https://claude.ai/download) and drag it to `/Applications`.

---

## How it works

Claude Desktop is an Electron app. Its UI code is packed inside `app.asar`.

1. Extracts `app.asar`
2. Injects a direction-detection script into the renderer
3. Repacks the archive and computes the new SHA-256 header hash
4. **Windows:** Patches `claude.exe` to accept the new hash, swaps the integrity certificate in `cowork-svc.exe`, re-signs both
5. **macOS:** Updates `Info.plist` integrity hashes, re-signs the app bundle with an ad-hoc signature

Backups of original files are preserved (`.bak`) on Windows.

---

## Disclaimer

This tool modifies Claude Desktop's internal files without Anthropic's authorization and may violate their Terms of Service. Use at your own risk.

---

*by [adirbenmeir](https://github.com/adirbenmeir)*
