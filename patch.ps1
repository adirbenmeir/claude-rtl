<#
.SYNOPSIS
    Claude Desktop RTL Patcher — Hebrew & Arabic Support for Windows
.DESCRIPTION
    Patches Claude Desktop to support right-to-left text rendering.
    Works by injecting a smart direction-detection script into the app bundle,
    updating integrity hashes, and re-signing modified executables.
.AUTHOR
    adirbenmeir — https://github.com/adirbenmeir/claude-rtl
.VERSION
    1.0.0
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Constants ----------------------------------------------------------------
$global:VERSION       = '1.0.0'
$global:REPO          = 'adirbenmeir/claude-rtl'
$global:RAW_BASE      = "https://raw.githubusercontent.com/$global:REPO/main"
$global:WORK_DIR      = Join-Path $env:TEMP 'adir_rtl_work'
$global:CERT_NAME     = 'Adir_RTL_Cert'
$global:ASAR_TOOL     = 'asar'

# --- RTL JavaScript payload (injected into Claude's renderer) -----------------
$global:RTL_PAYLOAD = @'
;(function () {
    'use strict';

    if (typeof document === 'undefined') return;
    if (window.__adir_rtl_loaded__) return;
    window.__adir_rtl_loaded__ = true;

    const SEL = {
        message:  '.font-claude-message, .font-claude-response-body, .standard-markdown',
        input:    '[data-testid="chat-input"], [contenteditable="true"]',
        block:    'pre, code, .code-block__code',
        inline:   'p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th',
        lists:    'ol, ul',
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
            if (isRTL(ch)) { rtl++; if (firstStrong === null) firstStrong = 'rtl'; }
            else if (/\p{L}/u.test(ch)) { ltr++; if (firstStrong === null) firstStrong = 'ltr'; }
        }
        if (firstStrong === null) return false;
        const total = rtl + ltr;
        if (total === 0) return false;
        if (firstStrong === 'rtl') return (rtl / total) >= 0.2;
        return (rtl / total) >= 0.6;
    }

    function setRTL(el)   { el.style.direction='rtl'; el.style.textAlign='right'; el.style.unicodeBidi='plaintext'; }
    function clearDir(el) { el.style.direction=''; el.style.textAlign=''; el.style.unicodeBidi=''; }
    function lockLTR(el)  { el.style.direction='ltr'; el.style.textAlign='left'; el.style.unicodeBidi='embed'; }

    function injectBaseStyles() {
        if (document.getElementById('adir-rtl-styles')) return;
        const s = document.createElement('style');
        s.id = 'adir-rtl-styles';
        s.textContent = `
            p,li,h1,h2,h3,h4,h5,h6,blockquote,td,th { unicode-bidi:plaintext; direction:auto; }
            pre,code,.code-block__code { direction:ltr!important; text-align:left!important; unicode-bidi:embed!important; }
        `;
        document.head.appendChild(s);
    }

    function processCodeBlocks(root) { root.querySelectorAll(SEL.block).forEach(lockLTR); }

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
                el.style.direction='rtl'; el.style.paddingRight='1.5rem'; el.style.paddingLeft='0';
            } else {
                el.style.direction=''; el.style.paddingRight=''; el.style.paddingLeft='';
            }
        });
    }

    function processInput() {
        document.querySelectorAll(SEL.input).forEach(el => {
            const text = el.textContent || el.innerText || el.value || '';
            if (shouldRTL(text)) { el.style.direction='rtl'; el.style.textAlign='right'; el.style.paddingRight='1.5rem'; }
            else { el.style.direction='ltr'; el.style.textAlign='left'; el.style.paddingRight=''; }
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
        processCodeBlocks(document.body);
    }

    function onInput(e) {
        const t = e.target;
        if (!t) return;
        const ok = t.tagName==='TEXTAREA'||t.tagName==='INPUT'||t.isContentEditable;
        if (!ok) return;
        const text = t.value||t.textContent||t.innerText||'';
        if (shouldRTL(text)) { t.style.direction='rtl'; t.style.textAlign='right'; t.style.paddingRight='1.5rem'; }
        else { t.style.direction='ltr'; t.style.textAlign='left'; t.style.paddingRight=''; }
    }

    let _d = null;
    const obs = new MutationObserver(muts => {
        if (!muts.some(m => m.addedNodes.length > 0 || m.type==='characterData')) return;
        clearTimeout(_d);
        _d = setTimeout(processAll, 60);
    });

    function boot() {
        injectBaseStyles();
        processAll();
        document.addEventListener('input', onInput, true);
        obs.observe(document.body, { childList:true, subtree:true, characterData:true });
    }

    document.readyState === 'loading'
        ? document.addEventListener('DOMContentLoaded', boot)
        : boot();
})();
'@

# --- Console helpers -----------------------------------------------------------
function Write-Header {
    Clear-Host
    Write-Host ''
    Write-Host '  ######+ ########+##+     ' -ForegroundColor Blue
    Write-Host '  ##+══##++══##+══+##|     ' -ForegroundColor Blue
    Write-Host '  ######++   ##|   ##|     ' -ForegroundColor Blue
    Write-Host '  ##+══##+   ##|   ##|     ' -ForegroundColor Blue
    Write-Host '  ##|  ##|   ##|   #######+' -ForegroundColor Blue
    Write-Host '  +═+  +═+   +═+   +══════+' -ForegroundColor Blue
    Write-Host ''
    Write-Host "  Claude Desktop RTL Patcher  v$global:VERSION" -ForegroundColor White
    Write-Host "  github.com/$global:REPO" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('-' * 50) -ForegroundColor DarkGray
    Write-Host ''
}

function Write-Step([string]$msg)    { Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)      { Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg)    { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg)    { Write-Host "  [x] $msg" -ForegroundColor Red }
function Write-Section([string]$msg) { Write-Host "  $msg" -ForegroundColor Magenta }

# --- Elevation ----------------------------------------------------------------
function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) { return }

    Write-Warn 'Needs admin rights — re-launching elevated...'
    $scriptPath = $MyInvocation.ScriptName

    if ($scriptPath) {
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    } else {
        $tmp = Join-Path $env:TEMP 'adir_rtl_run.ps1'
        Invoke-RestMethod "$global:RAW_BASE/patch.ps1" -OutFile $tmp
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmp`""
    }
    exit
}

# --- Locate Claude ------------------------------------------------------------
function Get-ClaudeDir {
    $pkg = Get-AppxPackage | Where-Object { $_.Name -like '*Claude*' -and $_.InstallLocation } | Select-Object -First 1
    if ($pkg) { return $pkg.InstallLocation }
    throw 'Claude Desktop installation not found. Is it installed from the Microsoft Store?'
}

# --- Binary helpers -----------------------------------------------------------
function Search-Bytes([byte[]]$data, [byte[]]$pattern, [int]$from = 0) {
    for ($i = $from; $i -le $data.Length - $pattern.Length; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $pattern.Length; $j++) {
            if ($data[$i + $j] -ne $pattern[$j]) { $ok = $false; break }
        }
        if ($ok) { return $i }
    }
    return -1
}

function Get-AsarHeaderHash([string]$path) {
    $fs = [IO.File]::OpenRead($path)
    $br = New-Object IO.BinaryReader($fs)
    $fs.Seek(12, [IO.SeekOrigin]::Begin) | Out-Null
    $len = $br.ReadUInt32()
    if ($len -le 0 -or $len -gt 10MB) { $fs.Close(); throw "Unexpected ASAR header size: $len" }
    $bytes = $br.ReadBytes($len)
    $fs.Close()

    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($bytes)))
    return ([BitConverter]::ToString($hash) -replace '-').ToLower()
}

function Wait-Unlocked([string]$path, [int]$timeout = 20) {
    for ($i = 0; $i -lt $timeout; $i++) {
        try {
            $fs = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
            $fs.Close()
            return
        } catch { Start-Sleep 1 }
    }
    throw "File still locked after ${timeout}s: $path"
}

# --- Process management -------------------------------------------------------
function Stop-Claude {
    Write-Step 'Stopping Claude processes...'

    $svc = Get-WmiObject Win32_Service | Where-Object { $_.PathName -match 'cowork-svc' }
    if ($svc) {
        Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
        $waited = 0
        while ((Get-Service $svc.Name -ErrorAction SilentlyContinue).Status -ne 'Stopped' -and $waited -lt 10) {
            Start-Sleep 1; $waited++
        }
    }

    foreach ($name in @('claude', 'cowork-svc')) {
        Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep 2
    Write-OK 'Processes stopped'
}

function Start-Claude {
    Write-Step 'Restarting Claude...'

    $svc = Get-WmiObject Win32_Service | Where-Object { $_.PathName -match 'cowork-svc' }
    if ($svc) {
        Stop-Process -Name 'cowork-svc' -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
        try {
            Start-Service $svc.Name -ErrorAction Stop
            Write-OK "Service '$($svc.Name)' started"
        } catch {
            Write-Warn "Could not start service: $_"
        }
    }

    try {
        $pkg = Get-AppxPackage | Where-Object { $_.Name -like '*Claude*' } | Select-Object -First 1
        if ($pkg) {
            Start-Process "shell:AppsFolder\$($pkg.PackageFamilyName)!Claude"
            Write-OK 'Claude Desktop launched'
        }
    } catch {
        Write-Warn 'Could not auto-launch Claude — please open it manually'
    }
}

# --- Permissions --------------------------------------------------------------
function Grant-Access([string]$path) {
    cmd /c "takeown /F `"$path`" /R /D Y >nul 2>&1"
    cmd /c "icacls `"$path`" /grant Administrators:F /T /Q >nul 2>&1"
}

# --- Core: Install ------------------------------------------------------------
function Install-RTL {
    Write-Section 'Installing RTL patch...'
    Write-Host ''

    $claudeDir   = Get-ClaudeDir
    $appDir      = Join-Path $claudeDir 'app'
    $resDir      = Join-Path $appDir 'resources'
    $asarPath    = Join-Path $resDir 'app.asar'
    $exePath     = Join-Path $appDir 'claude.exe'
    $svcPath     = Join-Path $resDir 'cowork-svc.exe'

    if (-not (Test-Path $asarPath)) { throw "app.asar not found at: $asarPath" }

    # Check Node/asar
    try { 
        $asarCheck = cmd.exe /c 'npx --yes asar --version 2>&1'
        if ($LASTEXITCODE -ne 0) { throw 'asar missing' }
    } catch { 
        throw 'Node.js is required. Install from nodejs.org' 
    }

    # Install asar globally if not already installed (speeds up future runs)
    $asarGlobal = cmd.exe /c 'asar --version 2>&1'
    if ($LASTEXITCODE -ne 0) {
        Write-Step 'Installing asar globally for faster future runs...'
        cmd.exe /c 'npm install -g asar' | Out-Null
        Write-OK 'asar installed globally'
    }

    Stop-Claude

    Write-Step 'Acquiring permissions...'
    Grant-Access $appDir
    Grant-Access $resDir
    Write-OK 'Permissions granted'

    # Backup
    Write-Step 'Creating backups...'
    foreach ($f in @($asarPath, $exePath, $svcPath)) {
        if ((Test-Path $f) -and -not (Test-Path "$f.bak")) {
            Copy-Item $f "$f.bak" -Force
            Write-OK "Backed up: $(Split-Path $f -Leaf)"
        }
    }

    try {
        # -- Phase 1: Inject RTL into ASAR -------------------------------------
        Write-Step 'Reading ASAR integrity hash...'
        $oldHash = Get-AsarHeaderHash $asarPath
        Write-OK "Original hash: $oldHash"

        if (Test-Path $global:WORK_DIR) { Remove-Item $global:WORK_DIR -Recurse -Force }

        Write-Step 'Extracting app bundle...'
        asar extract $asarPath $global:WORK_DIR 2>&1 | Out-Null
        Write-OK 'Bundle extracted'

        Write-Step 'Injecting RTL script...'
        $buildDir = Join-Path $global:WORK_DIR '.vite\build'
        $injected = 0

        if (Test-Path $buildDir) {
            Get-ChildItem $buildDir -Filter '*.js' -Recurse | ForEach-Object {
                $content = Get-Content $_.FullName -Raw
                if ($content -notmatch '__adir_rtl_loaded__') {
                    [IO.File]::WriteAllText($_.FullName, $global:RTL_PAYLOAD + "`n" + $content, [Text.Encoding]::UTF8)
                    $injected++
                }
            }
        }

        if ($injected -eq 0) { Write-Warn 'No JS files found or already patched' }
        else { Write-OK "RTL injected into $injected file(s)" }

        Write-Step 'Repacking bundle...'
        $newAsar = "$asarPath.new"
        asar pack $global:WORK_DIR $newAsar 2>&1 | Out-Null

        $newHash = Get-AsarHeaderHash $newAsar
        Write-OK "New hash: $newHash"
        Move-Item $newAsar $asarPath -Force

        # -- Phase 2: Patch claude.exe hash ------------------------------------
        Write-Step 'Patching executable integrity...'

        $srcExe = if (Test-Path "$exePath.bak") { "$exePath.bak" } else { $exePath }
        $srcSvc = if (Test-Path "$svcPath.bak") { "$svcPath.bak" } else { $svcPath }

        Wait-Unlocked $exePath

        $exeBytes  = [IO.File]::ReadAllBytes($srcExe)
        $oldBytes  = [Text.Encoding]::ASCII.GetBytes($oldHash)
        $newBytes  = [Text.Encoding]::ASCII.GetBytes($newHash)
        $replaced  = 0
        $offset    = 0

        while ($true) {
            $idx = Search-Bytes $exeBytes $oldBytes $offset
            if ($idx -lt 0) { break }
            [Array]::Copy($newBytes, 0, $exeBytes, $idx, $newBytes.Length)
            $offset = $idx + $newBytes.Length
            $replaced++
        }

        if ($replaced -gt 0) {
            [IO.File]::WriteAllBytes($exePath, $exeBytes)
            Write-OK "Hash updated in claude.exe ($replaced occurrence(s))"
        } else {
            Write-Warn 'Hash not found in claude.exe — skipping'
        }

        # -- Phase 3: Certificate swap in cowork-svc.exe -----------------------
        if ((Test-Path $exePath) -and (Test-Path $svcPath)) {
            Write-Step 'Generating signing certificate...'

            $anchor    = [Text.Encoding]::ASCII.GetBytes('Anthropic, PBC')
            $svcBytes  = [IO.File]::ReadAllBytes($srcSvc)
            $holeStart = -1
            $holeSize  = 0
            $off       = 0

            while ($true) {
                $apos = Search-Bytes $svcBytes $anchor $off
                if ($apos -lt 0) { break }
                $limit = [Math]::Max(0, $apos - 2000)
                for ($i = $apos; $i -ge $limit; $i--) {
                    if ($svcBytes[$i] -eq 0x30 -and $svcBytes[$i+1] -eq 0x82) {
                        $sz = 4 + (([int]$svcBytes[$i+2] -shl 8) -bor $svcBytes[$i+3])
                        if ($sz -gt 500 -and $sz -lt 4000 -and ($i + $sz) -gt $apos) {
                            $holeStart = $i; $holeSize = $sz; break
                        }
                    }
                }
                if ($holeStart -ge 0) { break }
                $off = $apos + 1
            }

            if ($holeStart -lt 0) { throw 'Certificate hole not found in cowork-svc.exe' }

            $origSig = Get-AuthenticodeSignature $srcExe
            $subject = if ($origSig.SignerCertificate) { $origSig.SignerCertificate.Subject } else { 'CN=RTL-Patcher' }

            $cert    = $null
            $found   = $false
            $store   = New-Object Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
            $store.Open('ReadWrite')

            for ($attempt = 1; $attempt -le 12; $attempt++) {
                $cert = New-SelfSignedCertificate -Subject $subject -Type CodeSigningCert `
                    -CertStoreLocation 'Cert:\LocalMachine\My' -FriendlyName $global:CERT_NAME `
                    -KeyAlgorithm RSA -KeyLength 2048
                if ($cert.RawData.Length -le $holeSize) {
                    $store.Add($cert); $found = $true
                    Write-OK "Certificate generated ($($cert.RawData.Length) bytes, hole: $holeSize bytes)"
                    break
                }
                Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $cert.Thumbprint } | Remove-Item -ErrorAction SilentlyContinue
            }
            $store.Close()

            if (-not $found) { throw 'Could not generate a suitably sized certificate after 12 attempts' }

            # Patch cowork-svc
            Wait-Unlocked $svcPath
            $patch = New-Object byte[] $holeSize
            [Array]::Copy($cert.RawData, 0, $patch, 0, $cert.RawData.Length)
            [Array]::Copy($patch, 0, $svcBytes, $holeStart, $holeSize)
            [IO.File]::WriteAllBytes($svcPath, $svcBytes)
            Write-OK 'Certificate swapped in cowork-svc.exe'

            # Re-sign both
            foreach ($target in @($exePath, $svcPath)) {
                $result = Set-AuthenticodeSignature $target $cert -HashAlgorithm SHA256
                if ($result.Status -eq 'Valid') { Write-OK "Signed: $(Split-Path $target -Leaf)" }
                else { throw "Signing failed for $(Split-Path $target -Leaf): $($result.Status)" }
            }
        }

        # Cleanup
        if (Test-Path $global:WORK_DIR) { Remove-Item $global:WORK_DIR -Recurse -Force }

        Start-Claude

        Write-Host ''
        Write-Host ('-' * 50) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  RTL patch installed successfully.' -ForegroundColor Green
        Write-Host '  Hebrew and Arabic text will now render correctly.' -ForegroundColor Green
        Write-Host ''

    } catch {
        Write-Host ''
        Write-Fail "Installation failed: $($_.Exception.Message)"
        Write-Warn 'Rolling back to original state...'
        Uninstall-RTL -Silent
        throw 'Installation aborted. Your Claude installation was restored.'
    }
}

# --- Core: Uninstall ----------------------------------------------------------
function Uninstall-RTL([switch]$Silent) {
    if (-not $Silent) {
        Write-Section 'Removing RTL patch...'
        Write-Host ''
    }

    $claudeDir = Get-ClaudeDir
    $appDir    = Join-Path $claudeDir 'app'
    $resDir    = Join-Path $appDir 'resources'

    Stop-Claude
    Grant-Access $appDir
    Grant-Access $resDir

    $targets = @(
        @{ orig = Join-Path $resDir 'app.asar';     bak = Join-Path $resDir 'app.asar.bak' }
        @{ orig = Join-Path $appDir 'claude.exe';   bak = Join-Path $appDir 'claude.exe.bak' }
        @{ orig = Join-Path $resDir 'cowork-svc.exe'; bak = Join-Path $resDir 'cowork-svc.exe.bak' }
    )

    foreach ($t in $targets) {
        if (Test-Path $t.bak) {
            Copy-Item $t.bak $t.orig -Force
            if (-not $Silent) { Write-OK "Restored: $(Split-Path $t.orig -Leaf)" }
        }
    }

    foreach ($store in @('My', 'Root')) {
        Get-ChildItem "Cert:\LocalMachine\$store" |
            Where-Object { $_.FriendlyName -eq $global:CERT_NAME } |
            Remove-Item -ErrorAction SilentlyContinue
    }

    Start-Claude

    if (-not $Silent) {
        Write-Host ''
        Write-Host '  Claude restored to original state.' -ForegroundColor Green
        Write-Host ''
    }
}

# --- Menu ---------------------------------------------------------------------
function Show-Menu {
    Write-Header

    Write-Host '  What would you like to do?' -ForegroundColor White
    Write-Host ''
    Write-Host '    1  ->  Install RTL patch' -ForegroundColor Cyan
    Write-Host '    2  ->  Remove patch & restore Claude' -ForegroundColor Cyan
    Write-Host '    3  ->  Exit' -ForegroundColor DarkGray
    Write-Host ''

    $choice = (Read-Host '  Choice').Trim()

    switch ($choice) {
        '1' {
            Write-Host ''
            Write-Host '  This will briefly close Claude Desktop.' -ForegroundColor Yellow
            $ok = (Read-Host '  Continue? (Y/n)').Trim()
            if ($ok -ne 'n' -and $ok -ne 'N') {
                try { Install-RTL } catch { Write-Fail $_.Exception.Message }
            }
        }
        '2' {
            Write-Host ''
            Write-Host '  This will remove the patch and restore the original files.' -ForegroundColor Yellow
            $ok = (Read-Host '  Continue? (Y/n)').Trim()
            if ($ok -ne 'n' -and $ok -ne 'N') {
                try { Uninstall-RTL } catch { Write-Fail $_.Exception.Message }
            }
        }
        '3' { return }
        default {
            Write-Warn 'Invalid choice'
            Start-Sleep 1
            Show-Menu
            return
        }
    }

    Write-Host ''
    Read-Host '  Press Enter to exit'
}

# --- Entry point --------------------------------------------------------------
Assert-Admin
Show-Menu
