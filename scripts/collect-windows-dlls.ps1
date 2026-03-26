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
Write-Host "`n[3/3] Copying VC++ runtime DLLs ..."

# Search common VS 2022 redist locations for the CRT x64 directory.
$vsBase = "C:\Program Files\Microsoft Visual Studio\2022"
$crtDirs = @(
    # MSVC toolset 14.3x (VS 2022)
    "$vsBase\Professional\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "$vsBase\Enterprise\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "$vsBase\Community\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT",
    "$vsBase\BuildTools\VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT"
)

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
        $crtFound = $true
        break
    }
}

if (-not $crtFound) {
    # Fall back to whatever is in System32 (already on any machine with VS)
    Write-Warning "VC++ Redist dir not found — runtime DLLs not copied."
    Write-Warning "Install 'Microsoft Visual C++ Redistributable (x64)' on target machines."
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
