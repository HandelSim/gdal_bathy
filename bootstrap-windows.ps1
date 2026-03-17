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
# 3. Build GDAL from repo source
# ---------------------------------------------------------------------------
if (Test-Path "$GdalInst\include\gdal.h") {
    Write-Host ""
    Write-Host "GDAL already built at $GdalInst - skipping build."
} else {
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
        "-DCMAKE_PREFIX_PATH=$SdkRoot",
        "-DPROJ_ROOT=$SdkRoot",
        "-DHDF5_ROOT=$SdkRoot",
        "-DBUILD_SHARED_LIBS=ON",
        "-DGDAL_BUILD_OPTIONAL_DRIVERS=OFF",
        "-DOGR_BUILD_OPTIONAL_DRIVERS=OFF",
        "-DGDAL_ENABLE_DRIVER_HDF5=ON",
        "-DGDAL_ENABLE_DRIVER_GTIFF=ON",
        "-DBUILD_APPS=OFF",
        "-DBUILD_TESTING=OFF"
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
