<#
.SYNOPSIS
    Collects all runtime DLLs needed by bathymetry.lib / test_bathymetry.exe
    into deps\gdal\bin\ and deps\gsf\lib\ so the project is fully self-contained.

.DESCRIPTION
    Run this once on your Windows build machine after a successful build.
    It copies:
      - Every DLL from vcpkg's installed/x64-windows/bin/  (GDAL + all transitive deps)
      - The GSF DLL produced by the CMake build
      - The VC++ runtime DLLs from the VS 2022 redistributable

    After running, commit deps\gdal\bin\ and deps\gsf\lib\ to the repo.

.PARAMETER VcpkgRoot
    Root of your vcpkg installation.  Defaults to C:\Developer\vcpkg.

.PARAMETER BuildDir
    CMake binary dir that contains the Release\ output.  Defaults to build\Release
    relative to the repo root.

.PARAMETER Triplet
    vcpkg triplet.  Defaults to x64-windows.

.EXAMPLE
    # From the repo root:
    powershell -ExecutionPolicy Bypass -File scripts\collect-windows-dlls.ps1

    # With custom vcpkg location:
    powershell -ExecutionPolicy Bypass -File scripts\collect-windows-dlls.ps1 `
        -VcpkgRoot D:\vcpkg
#>
param(
    [string]$VcpkgRoot  = "C:\Developer\vcpkg",
    [string]$BuildDir   = "",          # auto-detected when empty
    [string]$Triplet    = "x64-windows"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Resolve repo root (parent of this script) ────────────────────────────────
$RepoRoot = Split-Path -Parent $PSScriptRoot

# ── Resolve build dir ────────────────────────────────────────────────────────
if (-not $BuildDir) {
    $BuildDir = Join-Path $RepoRoot "build\Release"
}
if (-not (Test-Path $BuildDir)) {
    Write-Error "Build dir not found: $BuildDir`nRun 'cmake --build build --preset windows-vcpkg-release' first."
    exit 1
}

# ── Destination dirs ─────────────────────────────────────────────────────────
$GdalBinDst = Join-Path $RepoRoot "deps\gdal\bin"
$GsfLibDst  = Join-Path $RepoRoot "deps\gsf\lib"

New-Item -ItemType Directory -Force -Path $GdalBinDst | Out-Null
New-Item -ItemType Directory -Force -Path $GsfLibDst  | Out-Null

$copied  = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()

function Copy-DLL {
    param([string]$Src, [string]$DstDir)
    $leaf = Split-Path -Leaf $Src
    $dst  = Join-Path $DstDir $leaf
    if (Test-Path $dst) {
        $skipped.Add($leaf) | Out-Null
    } else {
        Copy-Item -Path $Src -Destination $dst -Force
        $copied.Add($leaf) | Out-Null
    }
}

# ── 1. vcpkg DLLs ─────────────────────────────────────────────────────────────
$vcpkgBin = Join-Path $VcpkgRoot "installed\$Triplet\bin"
if (-not (Test-Path $vcpkgBin)) {
    Write-Warning "vcpkg bin dir not found: $vcpkgBin — skipping vcpkg DLLs."
} else {
    Write-Host "`n[1/3] Copying vcpkg DLLs from $vcpkgBin ..."
    Get-ChildItem -Path $vcpkgBin -Filter "*.dll" | ForEach-Object {
        Copy-DLL -Src $_.FullName -DstDir $GdalBinDst
    }
}

# ── 2. GSF DLL (built by CMake) ───────────────────────────────────────────────
Write-Host "`n[2/3] Copying GSF DLL from $BuildDir ..."
$gsfDll = Join-Path $BuildDir "gsf.dll"
if (Test-Path $gsfDll) {
    Copy-DLL -Src $gsfDll -DstDir $GdalBinDst   # next to the other runtime DLLs
    Copy-Item -Path $gsfDll -Destination $GsfLibDst -Force   # also keep a copy here
    $gsfImp = Join-Path $BuildDir "gsf.lib"
    if (Test-Path $gsfImp) {
        Copy-Item -Path $gsfImp -Destination $GsfLibDst -Force
        Write-Host "  Copied gsf.dll + gsf.lib (import lib) -> deps\gsf\lib\"
    } else {
        Write-Host "  Copied gsf.dll -> deps\gsf\lib\"
    }
} else {
    # Some generators put it one level deeper (e.g. deps\gsf\Release\gsf.dll)
    $gsfDll2 = Join-Path $BuildDir "..\deps\gsf\Release\gsf.dll"
    if (Test-Path $gsfDll2) {
        Copy-DLL -Src (Resolve-Path $gsfDll2).Path -DstDir $GdalBinDst
        Copy-Item -Path (Resolve-Path $gsfDll2).Path -Destination $GsfLibDst -Force
        Write-Host "  Copied gsf.dll from deps\gsf\Release\"
    } else {
        Write-Warning "gsf.dll not found in $BuildDir — build the project first."
    }
}

# ── 3. VC++ runtime DLLs ──────────────────────────────────────────────────────
Write-Host "`n[3/4] Copying VC++ runtime DLLs ..."

# Search common VS 2022 redist locations for the CRT x64 directory.
$vsBase = "C:\Program Files\Microsoft Visual Studio\2022"
$crtDirs = @(
    # MSVC toolset 14.3x (VS 2022)
    "$vsBase\Professional\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "$vsBase\Enterprise\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "$vsBase\Community\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "$vsBase\BuildTools\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT"
)

# Desktop CRT DLLs (needed by anything built with MSVC)
$crtDllNames = @(
    "msvcp140.dll",
    "msvcp140_1.dll",
    "msvcp140_2.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "concrt140.dll"
)

$crtFound = $false
foreach ($pattern in $crtDirs) {
    $matches_ = Resolve-Path $pattern -ErrorAction SilentlyContinue
    if ($matches_) {
        $crtDir = ($matches_ | Select-Object -Last 1).Path   # pick newest version
        Write-Host "  Using CRT dir: $crtDir"
        foreach ($dll in $crtDllNames) {
            $src = Join-Path $crtDir $dll
            if (Test-Path $src) { Copy-DLL -Src $src -DstDir $GdalBinDst }
        }

        # vcruntime140_app.dll lives in the CRTapp sibling directory.
        # It is required if any dependency was compiled targeting UWP/AppContainer.
        $crtAppDir = $crtDir -replace 'Microsoft\.VC143\.CRT$', 'Microsoft.VC143.CRTapp'
        if (Test-Path $crtAppDir) {
            $appDll = Join-Path $crtAppDir "vcruntime140_app.dll"
            if (Test-Path $appDll) {
                Copy-DLL -Src $appDll -DstDir $GdalBinDst
                Write-Host "  Copied vcruntime140_app.dll (UWP CRT)"
            }
        } else {
            # Fallback: it may already be in System32 on the target machine.
            Write-Warning "vcruntime140_app.dll not found in VS Redist."
            Write-Warning "  It is normally present in C:\Windows\System32 on Windows 10/11."
            Write-Warning "  If missing, install the latest Windows Update or VS 2022 Redistributable."
        }

        $crtFound = $true
        break
    }
}

if (-not $crtFound) {
    Write-Warning "VC++ Redist dir not found — runtime DLLs not copied."
    Write-Warning "Install 'Microsoft Visual C++ Redistributable (x64)' on target machines."
}

# ── 4. OpenSSL legacy compatibility (ssleay32 / libeay32) ─────────────────────
# ssleay32.dll / libeay32.dll are the OpenSSL 1.0.x DLL names.
# They are NOT provided by OpenSSL 3 (which ships libssl-3-x64 / libcrypto-3-x64).
# If your software or a dependency imports ssleay32.dll it was compiled against
# OpenSSL 1.0.x.  Options:
#   A) Re-compile that dependency against OpenSSL 3 — the right long-term fix.
#   B) Install "Win64 OpenSSL v1.0.2u Light" from https://slproweb.com/products/Win32OpenSSL.html
#      and copy ssleay32.dll / libeay32.dll from its install dir (default C:\OpenSSL-Win64).
#   C) The shimming approach below copies them from a local OpenSSL 1.0.2 install if present.
Write-Host "`n[4/4] Checking for OpenSSL 1.0.x legacy DLLs (ssleay32 / libeay32) ..."
$openssl10Dirs = @(
    "C:\OpenSSL-Win64",
    "C:\OpenSSL",
    "C:\Program Files\OpenSSL-Win64",
    "C:\Program Files\OpenSSL"
)
$legacySslFound = $false
foreach ($d in $openssl10Dirs) {
    $ss = Join-Path $d "ssleay32.dll"
    $le = Join-Path $d "libeay32.dll"
    if ((Test-Path $ss) -or (Test-Path $le)) {
        if (Test-Path $ss) { Copy-DLL -Src $ss -DstDir $GdalBinDst; Write-Host "  Copied ssleay32.dll from $d" }
        if (Test-Path $le) { Copy-DLL -Src $le -DstDir $GdalBinDst; Write-Host "  Copied libeay32.dll from $d" }
        $legacySslFound = $true
        break
    }
}
if (-not $legacySslFound) {
    Write-Warning "ssleay32.dll / libeay32.dll not found."
    Write-Warning "  These are OpenSSL 1.0.x DLLs.  Install Win64 OpenSSL 1.0.2 from:"
    Write-Warning "    https://slproweb.com/products/Win32OpenSSL.html"
    Write-Warning "  or re-build the dependency that needs them against OpenSSL 3."
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Done."
Write-Host "  Newly copied : $($copied.Count) DLL(s)"
Write-Host "  Already present (skipped): $($skipped.Count) DLL(s)"
Write-Host ""
Write-Host "Contents of deps\gdal\bin\:"
Get-ChildItem $GdalBinDst -Filter "*.dll" | Sort-Object Name | ForEach-Object {
    Write-Host ("  " + $_.Name)
}
Write-Host ""
Write-Host "Next steps:"
Write-Host "  git add deps/gdal/bin/ deps/gsf/lib/"
Write-Host "  git commit -m 'chore: add all Windows runtime DLLs'"
