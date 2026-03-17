<#
.SYNOPSIS
    One-time setup: installs vcpkg and records VCPKG_ROOT so CMake can find it.

.DESCRIPTION
    Run this once from any PowerShell window before your first build.
    It does NOT require Administrator privileges.

    What it does:
      1. Clones vcpkg to C:\vcpkg (override with -VcpkgRoot)
      2. Downloads vcpkg.exe via Invoke-WebRequest (avoids tls12-download.exe,
         which is commonly blocked by corporate group policy)
      3. Persists VCPKG_ROOT as a user environment variable

    After this script finishes, open a new terminal and run:
      cmake --preset windows-vcpkg
      cmake --build build --preset windows-vcpkg-release

    On first configure, vcpkg downloads and builds GDAL plus all transitive
    dependencies (HDF5, PROJ, etc.) from the vcpkg.json in this repository.
    This takes ~10-20 minutes the first time; subsequent builds are instant.

.PARAMETER VcpkgRoot
    Where to install vcpkg. Defaults to C:\vcpkg.
#>
param(
    [string]$VcpkgRoot = "C:\vcpkg"
)

$ErrorActionPreference = "Stop"

# -- 1. Clone vcpkg if not already present ------------------------------------
if (-not (Test-Path "$VcpkgRoot\.git")) {
    Write-Host "Cloning vcpkg to $VcpkgRoot ..."
    git clone https://github.com/microsoft/vcpkg.git $VcpkgRoot
} else {
    Write-Host "vcpkg repo already present at $VcpkgRoot"
}

# -- 2. Download vcpkg.exe via Invoke-WebRequest ------------------------------
# The standard bootstrap-vcpkg.bat uses tls12-download.exe which can be
# blocked by corporate group policy. We replicate what it does using only
# built-in PowerShell cmdlets, which are not subject to that restriction.

if (-not (Test-Path "$VcpkgRoot\vcpkg.exe")) {
    # Read the pinned tool version from the repo metadata
    $metadataFile = "$VcpkgRoot\scripts\vcpkg-tool-metadata.txt"
    if (-not (Test-Path $metadataFile)) {
        throw "Cannot find $metadataFile - the vcpkg clone may be incomplete."
    }

    $versionDate = $null
    foreach ($line in Get-Content $metadataFile) {
        if ($line -match "^VCPKG_TOOL_RELEASE_TAG=(.+)$") {
            $versionDate = $Matches[1].Trim()
            break
        }
        # Older metadata files just have the tag on the first non-comment line
        if ($line -notmatch "^#" -and $line.Trim() -ne "") {
            $versionDate = $line.Trim()
            break
        }
    }

    if (-not $versionDate) {
        throw "Could not parse vcpkg tool version from $metadataFile"
    }

    $arch = if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq "Arm64") { "vcpkg-arm64.exe" } else { "vcpkg.exe" }
    $url = "https://github.com/microsoft/vcpkg-tool/releases/download/$versionDate/$arch"

    Write-Host "Downloading vcpkg.exe ($versionDate) ..."
    Invoke-WebRequest -Uri $url -OutFile "$VcpkgRoot\vcpkg.exe" -UseBasicParsing
    Write-Host "vcpkg.exe downloaded successfully."
} else {
    Write-Host "vcpkg.exe already present."
}

# -- 3. Persist VCPKG_ROOT for the current user -------------------------------
[System.Environment]::SetEnvironmentVariable("VCPKG_ROOT", $VcpkgRoot, "User")
$env:VCPKG_ROOT = $VcpkgRoot
Write-Host "VCPKG_ROOT set to $VcpkgRoot (user environment, permanent)"

# -- 4. Print next steps ------------------------------------------------------
Write-Host ""
Write-Host "Setup complete. Open a NEW terminal (so VCPKG_ROOT is visible) and run:"
Write-Host ""
Write-Host "  cmake --preset windows-vcpkg"
Write-Host "  cmake --build build --preset windows-vcpkg-release"
Write-Host ""
Write-Host "The first cmake configure will download and build all dependencies"
Write-Host "(GDAL, HDF5, PROJ, ...) automatically via vcpkg - this takes ~10-20 min."
Write-Host "Subsequent builds are instant (packages are cached in vcpkg)."
Write-Host ""
Write-Host "To run the test executable afterwards:"
Write-Host "  set GDAL_DATA=$VcpkgRoot\installed\x64-windows\share\gdal"
Write-Host "  build\Release\test_bathymetry.exe"
