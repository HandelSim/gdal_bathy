<#
.SYNOPSIS
    One-time setup: downloads the GISInternals dependency kit and builds GDAL
    from the repo's own source tree - no vcpkg, no pre-built executables needed.

.DESCRIPTION
    Designed for corporate environments where group policy blocks downloaded
    executables.  This script uses only:
      - Invoke-WebRequest / Expand-Archive  (PowerShell built-ins, not exes)
      - cmake.exe / cl.exe  (trusted Visual Studio tools)

    What it does:
      1. Locates Visual Studio 2022 and initialises the MSVC x64 environment
      2. Downloads release-1944-x64-dev.zip from gisinternals.com (~50 MB)
         This is a ZIP of pre-compiled MSVC 2022 x64 dependencies:
         SQLite, PROJ, HDF5, libtiff, zlib, curl, etc.
         (a ZIP file, not an executable - nothing is run from it directly)
      3. Extracts the kit to windows-deps\sdk\
      4. Configures GDAL 3.12 (source already in the repo at gdal-3.12.2\)
         with minimal drivers: HDF5 + BAG + GeoTIFF only.  All optional
         drivers and apps are disabled for a fast build.
      5. Builds + installs GDAL to windows-deps\gdal\
      6. Copies dependency DLLs into windows-deps\gdal\bin\ so one PATH
         entry covers everything at runtime

    After this script finishes (~20-40 min first time), open a NEW terminal and:
      cmake --preset windows-local
      cmake --build build --preset windows-local-release

.PARAMETER VcpkgRoot
    Ignored - kept for backward compat if called with -VcpkgRoot.
#>
param([string]$VcpkgRoot)

$ErrorActionPreference = "Stop"
$RepoRoot  = $PSScriptRoot
$WinDeps   = "$RepoRoot\windows-deps"
$DevKitZip = "$WinDeps\devkit.zip"
$SdkRoot   = "$WinDeps\sdk"
$GdalSrc   = "$RepoRoot\gdal-3.12.2"
$GdalBld   = "$WinDeps\gdal-build"
$GdalInst  = "$WinDeps\gdal"

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
if (-not (Test-Path "$RepoRoot\CMakeLists.txt")) {
    throw "Run this script from the repo root (the directory containing CMakeLists.txt)."
}

# ---------------------------------------------------------------------------
# 0b. Download GDAL source if not present
#     gdal-3.12.2\ is gitignored so it is not in the repo checkout.
#     GitHub archive ZIPs extract to gdal-3.12.2\ (the 'v' prefix is stripped).
# ---------------------------------------------------------------------------
if (-not (Test-Path $GdalSrc)) {
    $GdalZipUrl = "https://github.com/OSGeo/gdal/archive/refs/tags/v3.12.2.zip"
    $GdalZip    = "$RepoRoot\gdal-3.12.2-src.zip"
    Write-Host ""
    Write-Host "Downloading GDAL 3.12.2 source (~120 MB) ..."
    Write-Host "  $GdalZipUrl"
    try {
        Invoke-WebRequest -Uri $GdalZipUrl -OutFile $GdalZip -UseBasicParsing
    } catch {
        throw "Failed to download GDAL source: $_"
    }
    Write-Host "Extracting GDAL source ..."
    Expand-Archive -Path $GdalZip -DestinationPath $RepoRoot -Force
    Remove-Item $GdalZip -ErrorAction SilentlyContinue
    if (-not (Test-Path $GdalSrc)) {
        throw "Extraction did not produce $GdalSrc - check the ZIP contents."
    }
    Write-Host "GDAL source ready at $GdalSrc"
} else {
    Write-Host "GDAL source already present at $GdalSrc"
}

# ---------------------------------------------------------------------------
# 1. Initialise MSVC x64 developer environment
#    vswhere.exe lives in C:\Program Files (x86)\... - a trusted system path.
# ---------------------------------------------------------------------------
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Initialising MSVC x64 environment ..."
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found.  Install Visual Studio 2022 with C++ tools."
    }
    $vsPath = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if (-not $vsPath) {
        throw "Visual Studio 2022 with C++ build tools not found."
    }
    $vcvars = "$vsPath\VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) {
        throw "vcvars64.bat not found at $vcvars"
    }
    # Import the VS developer environment into this PowerShell session
    $envLines = cmd /c "`"$vcvars`" >NUL 2>&1 && set"
    foreach ($line in $envLines) {
        if ($line -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
        }
    }
    Write-Host "MSVC environment ready."
} else {
    Write-Host "cl.exe already in PATH - skipping VS environment init."
}

# Verify cmake is available
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "cmake.exe not found.  Add cmake to PATH or install it via Visual Studio."
}

New-Item -ItemType Directory -Force -Path $WinDeps | Out-Null

# ---------------------------------------------------------------------------
# 2. Download the GISInternals dependency kit
#    Pre-built MSVC 2022 x64 binaries for all GDAL external deps.
#    Invoke-WebRequest is a PS built-in cmdlet - not a standalone exe.
# ---------------------------------------------------------------------------
$DevKitUrl = "https://download.gisinternals.com/sdk/downloads/release-1944-x64-dev.zip"

if (-not (Test-Path $SdkRoot)) {
    Write-Host ""
    Write-Host "Downloading GISInternals dependency kit (~50 MB) ..."
    Write-Host "  $DevKitUrl"
    try {
        Invoke-WebRequest -Uri $DevKitUrl -OutFile $DevKitZip -UseBasicParsing
    } catch {
        $msg = @(
            "Download failed: $_",
            "",
            "If you are behind a proxy, configure it first:",
            "  [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy('http://proxy:port')",
            "  [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials",
            "",
            "Alternatively, download the file manually and place it at:",
            "  $DevKitZip",
            "URL: $DevKitUrl",
            "Then re-run this script."
        )
        throw ($msg -join "`n")
    }

    Write-Host "Extracting dependency kit ..."
    $tmpDir = "$WinDeps\sdk-raw"
    Expand-Archive -Path $DevKitZip -DestinationPath $tmpDir -Force

    # Handle both flat ZIPs and ZIPs with a single top-level subdirectory
    $items = Get-ChildItem $tmpDir
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
        Move-Item $items[0].FullName $SdkRoot
        Remove-Item $tmpDir
    } else {
        Rename-Item $tmpDir $SdkRoot
    }
    Remove-Item $DevKitZip -ErrorAction SilentlyContinue
    Write-Host "Dependency kit extracted to $SdkRoot"
} else {
    Write-Host "Dependency kit already present at $SdkRoot"
}

# ---------------------------------------------------------------------------
# 2b. Probe the SDK to find exact paths for required dependencies.
#     The GISInternals dev kit is a flat (non-cmake) SDK; FindPROJ.cmake and
#     FindZLIB.cmake need explicit paths or they fail even with PREFIX_PATH.
# ---------------------------------------------------------------------------
function Find-SdkHeader([string]$Root, [string]$Name) {
    $hit = Get-ChildItem -Path $Root -Recurse -Filter $Name -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($hit) { return $hit.Directory.FullName }
    return $null
}
function Find-SdkLib([string]$Root, [string[]]$Names) {
    foreach ($n in $Names) {
        $hit = Get-ChildItem -Path $Root -Recurse -Filter $n -ErrorAction SilentlyContinue |
               Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}
# Wildcard variant - for versioned lib names like proj_9_5.lib
function Find-SdkLibWild([string]$Root, [string]$Pattern, [string[]]$Excludes = @()) {
    Get-ChildItem -Path $Root -Recurse -Filter $Pattern -ErrorAction SilentlyContinue |
        Where-Object { $name = $_.Name; ($Excludes | Where-Object { $name -like $_ }).Count -eq 0 } |
        Sort-Object Name |
        Select-Object -First 1 -ExpandProperty FullName
}

Write-Host ""
Write-Host "Probing SDK for dependency paths ..."

$ProjIncDir  = Find-SdkHeader  $SdkRoot "proj.h"
# GISInternals names the PROJ lib with a version suffix (e.g. proj_9_5.lib).
# Try canonical names first, then fall back to any proj*.lib.
$ProjLib     = Find-SdkLib     $SdkRoot @("proj_i.lib","proj.lib")
if (-not $ProjLib) {
    $ProjLib = Find-SdkLibWild $SdkRoot "proj*.lib" @("*_test*","*_util*","*_grids*")
    if ($ProjLib) { Write-Host "  (PROJ lib found via wildcard: $(Split-Path $ProjLib -Leaf))" }
}
$ZlibIncDir  = Find-SdkHeader $SdkRoot "zlib.h"
$ZlibLib     = Find-SdkLib   $SdkRoot @("zlib_i.lib","zlib.lib","zlibstatic.lib")
$Hdf5IncDir  = Find-SdkHeader $SdkRoot "hdf5.h"
$Hdf5Lib     = Find-SdkLib   $SdkRoot @("hdf5_i.lib","hdf5.lib","libhdf5.lib")

# Diagnostics - shown so failures are easy to interpret
foreach ($pair in @(
    @("proj.h",  $ProjIncDir),  @("PROJ lib", $ProjLib),
    @("zlib.h",  $ZlibIncDir),  @("ZLIB lib", $ZlibLib),
    @("hdf5.h",  $Hdf5IncDir),  @("HDF5 lib", $Hdf5Lib)
)) {
    $label = $pair[0]; $val = $pair[1]
    if ($val) { Write-Host "  Found $label : $val" }
    else      { Write-Warning "  $label NOT found in $SdkRoot" }
}

if (-not $ProjIncDir -or -not $ProjLib) {
    throw ("PROJ not found in SDK at $SdkRoot.`n" +
           "Expected proj.h under $SdkRoot\include and proj_i.lib under $SdkRoot\lib.`n" +
           "Re-download the dev kit or verify the ZIP structure.")
}
if (-not $ZlibIncDir -or -not $ZlibLib) {
    throw ("ZLIB not found in SDK at $SdkRoot.`n" +
           "Expected zlib.h and zlib_i.lib.`n" +
           "Re-download the dev kit or verify the ZIP structure.")
}

# Derive the true SDK inner root (the directory that contains include\ and lib\).
# GISInternals ZIPs sometimes nest one extra level (e.g. sdk\release-1944-x64\).
# $ZlibIncDir was found by searching recursively; its parent is always the real root.
$ActualSdkRoot = Split-Path $ZlibIncDir -Parent
if ($ActualSdkRoot -ne $SdkRoot) {
    Write-Host "  (Effective SDK root: $ActualSdkRoot)"
}

# Probe TIFF and GeoTIFF too; if missing, GDAL uses its internal bundled copies.
$TiffIncDir = Find-SdkHeader $SdkRoot "tiff.h"
$TiffLib    = Find-SdkLib   $SdkRoot @("libtiff_i.lib","libtiff.lib","tiff_i.lib","tiff.lib")
$GtiffIncDir = Find-SdkHeader $SdkRoot "geotiff.h"
$GtiffLib    = Find-SdkLib   $SdkRoot @("geotiff_i.lib","geotiff.lib")
foreach ($pair in @(@("tiff.h",$TiffIncDir),@("TIFF lib",$TiffLib),
                    @("geotiff.h",$GtiffIncDir),@("GeoTIFF lib",$GtiffLib))) {
    if ($pair[1]) { Write-Host "  Found $($pair[0]) : $($pair[1])" }
    else          { Write-Host "  $($pair[0]) not found - GDAL will use internal copy" }
}

# ---------------------------------------------------------------------------
# 3. Build GDAL from repo source
# ---------------------------------------------------------------------------
if (Test-Path "$GdalInst\include\gdal.h") {
    Write-Host ""
    Write-Host "GDAL already built at $GdalInst - skipping build."
} else {
    # Clean a stale build directory (previous run failed mid-way).
    # A fresh configure is needed whenever cmake args change.
    if (Test-Path $GdalBld) {
        Write-Host ""
        Write-Host "Removing stale build directory: $GdalBld"
        Remove-Item -Recurse -Force $GdalBld
    }

    Write-Host ""
    Write-Host "Configuring GDAL (minimal build: HDF5/BAG + GeoTIFF only) ..."
    Write-Host "  Source : $GdalSrc"
    Write-Host "  Build  : $GdalBld"
    Write-Host "  Install: $GdalInst"
    Write-Host ""

    $cmakeArgs = @(
        "-S", $GdalSrc,
        "-B", $GdalBld,
        "-G", "Visual Studio 17 2022",
        "-A", "x64",
        "-DCMAKE_INSTALL_PREFIX=$GdalInst",
        # Point cmake prefix at the real inner SDK root (include\ and lib\ live here)
        "-DCMAKE_PREFIX_PATH=$ActualSdkRoot",
        # PROJ - explicit paths; GISInternals has no cmake config files
        "-DPROJ_INCLUDE_DIR=$ProjIncDir",
        "-DPROJ_LIBRARY=$ProjLib",
        # HDF5 - point FindHDF5 at the real root that contains include\ and lib\
        "-DHDF5_ROOT=$ActualSdkRoot",
        "-DHDF5_C_INCLUDE_DIR=$Hdf5IncDir",
        # TIFF / GeoTIFF - pass explicit paths if found; otherwise GDAL uses bundled copies
        $(if ($TiffIncDir -and $TiffLib)   { "-DTIFF_INCLUDE_DIR=$TiffIncDir"; "-DTIFF_LIBRARY=$TiffLib" } else { $null }),
        $(if ($GtiffIncDir -and $GtiffLib) { "-DGEOTIFF_INCLUDE_DIR=$GtiffIncDir"; "-DGEOTIFF_LIBRARY=$GtiffLib" } else { $null }),
        "-DBUILD_SHARED_LIBS=ON",
        "-DGDAL_BUILD_OPTIONAL_DRIVERS=OFF",
        "-DOGR_BUILD_OPTIONAL_DRIVERS=OFF",
        "-DGDAL_ENABLE_DRIVER_HDF5=ON",
        "-DGDAL_ENABLE_DRIVER_GTIFF=ON",
        "-DBUILD_APPS=OFF",
        "-DBUILD_TESTING=OFF",
        # Use GDAL's bundled static zlib instead of the GISInternals DLL import lib.
        # The GISInternals zlib.lib is an import lib (expects zlib1.dll at link time)
        # but GDAL's headers see crc32 as a plain symbol -> LNK2019 on crc32.
        # HDF5.dll carries its own zlib dependency so this does not affect HDF5.
        "-DGDAL_USE_ZLIB_INTERNAL=ON",
        # Disable the GDAL algorithm framework (gdal raster tile, slope, etc.).
        # gdalalg_raster_tile.cpp calls crc32() directly from zlib headers but the
        # internal zlib renames all symbols, so the symbol is unresolvable.
        # We only need HDF5/BAG + GeoTIFF drivers, not the algorithm framework.
        "-DGDAL_ENABLE_ALGORITHMS=OFF",
        # Disable muparser: GISInternals ships it as a static lib but GDAL compiles
        # vrtexpression_muparser.obj expecting DLL-import symbols -> LNK2019 mismatch.
        "-DGDAL_USE_MUPARSER=OFF",
        # Disable WebP: newer libwebp splits SharpYuv into a separate lib not in SDK.
        "-DGDAL_USE_WEBP=OFF"
    )

    cmake @cmakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "GDAL cmake configure failed (exit $LASTEXITCODE). See output above."
    }

    Write-Host ""
    Write-Host "Building GDAL Release (~20-40 min first time) ..."
    cmake --build $GdalBld --config Release --target install
    if ($LASTEXITCODE -ne 0) {
        throw "GDAL build/install failed (exit $LASTEXITCODE). See output above."
    }
    Write-Host ""
    Write-Host "GDAL installed to $GdalInst"
}

# ---------------------------------------------------------------------------
# 4. Copy dependency DLLs into windows-deps\gdal\bin\
#    A single PATH entry then covers GDAL and all its runtime dependencies.
# ---------------------------------------------------------------------------
$gdalBin = "$GdalInst\bin"
New-Item -ItemType Directory -Force -Path $gdalBin | Out-Null

$sdkBin = "$SdkRoot\bin"
if (Test-Path $sdkBin) {
    Write-Host "Copying dependency DLLs from SDK to $gdalBin ..."
    Get-ChildItem "$sdkBin\*.dll" | ForEach-Object {
        Copy-Item $_.FullName $gdalBin -Force
    }
} else {
    Write-Warning "No bin\ directory in SDK at $sdkBin - DLLs may be missing at runtime."
}

# ---------------------------------------------------------------------------
# 5. Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host " Setup complete!"
Write-Host "============================================================"
Write-Host ""
Write-Host "Open a NEW terminal and build with:"
Write-Host ""
Write-Host "  cmake --preset windows-local"
Write-Host "  cmake --build build --preset windows-local-release"
Write-Host ""
Write-Host "If cmake was previously run and failed, delete build\ first:"
Write-Host "  Remove-Item -Recurse -Force build"
Write-Host ""
Write-Host "To run the test executable:"
Write-Host "  `$env:PATH += `";$gdalBin`""
Write-Host "  `$env:GDAL_DATA = `"$GdalInst\share\gdal`""
Write-Host "  build\Release\test_bathymetry.exe"
