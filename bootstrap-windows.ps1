<#
.SYNOPSIS
    One-time setup: installs vcpkg, downloads vcpkg.exe, and pre-builds all
    dependencies (GDAL, HDF5, PROJ, ...) so that cmake --preset windows-vcpkg
    succeeds immediately.

.DESCRIPTION
    Run this once from any PowerShell window before your first build.
    It does NOT require Administrator privileges.

    What it does:
      1. Clones vcpkg to C:\vcpkg (override with -VcpkgRoot)
      2. Downloads vcpkg.exe via Invoke-WebRequest (avoids tls12-download.exe,
         which is commonly blocked by corporate group policy)
      3. Unblocks vcpkg.exe so Windows does not treat it as an untrusted
         "downloaded-from-internet" file
      4. Installs all packages listed in vcpkg.json (GDAL + transitive deps)
         so cmake --preset windows-vcpkg finds everything pre-built (~10-20 min)
      5. Persists VCPKG_ROOT as a user environment variable

    After this script finishes, open a new terminal and run:
      cmake --preset windows-vcpkg
      cmake --build build --preset windows-vcpkg-release

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

# -- 3. Unblock vcpkg.exe -----------------------------------------------------
# Files downloaded from the internet carry a Zone.Identifier alternate data
# stream that causes Windows SmartScreen / Defender to prompt or block them.
# Unblock-File removes that mark so vcpkg.exe runs without interruption.
Unblock-File "$VcpkgRoot\vcpkg.exe"

# -- 4. Smoke-test vcpkg.exe --------------------------------------------------
Write-Host "Verifying vcpkg.exe ..."
$vcpkgOut = & "$VcpkgRoot\vcpkg.exe" version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error @"
vcpkg.exe failed to run (exit code $LASTEXITCODE):
  $vcpkgOut

Possible cause: a group policy or AppLocker rule is blocking executables
from $VcpkgRoot.  Try re-running with a different -VcpkgRoot, e.g.:
  .\bootstrap-windows.ps1 -VcpkgRoot "$env:LOCALAPPDATA\vcpkg"
"@
    exit 1
}
Write-Host ($vcpkgOut | Select-Object -First 1)

# -- 5. Pre-install all vcpkg dependencies ------------------------------------
# Running "vcpkg install" here (in manifest mode, reading vcpkg.json) populates
# the installed/ tree before cmake is invoked.  This gives visible progress
# output and catches download/build errors before cmake --preset runs.
Write-Host ""
Write-Host "Installing dependencies from vcpkg.json (GDAL + HDF5 + PROJ ...)."
Write-Host "First run takes ~10-20 minutes; subsequent runs are instant."
Write-Host ""
Push-Location $PSScriptRoot
& "$VcpkgRoot\vcpkg.exe" install --triplet x64-windows --no-print-usage
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Error "vcpkg install failed (exit code $LASTEXITCODE). See output above."
    exit 1
}
Pop-Location
Write-Host ""
Write-Host "All dependencies installed."

# -- 6. Persist VCPKG_ROOT for the current user -------------------------------
[System.Environment]::SetEnvironmentVariable("VCPKG_ROOT", $VcpkgRoot, "User")
$env:VCPKG_ROOT = $VcpkgRoot
Write-Host "VCPKG_ROOT set to $VcpkgRoot (user environment, permanent)"

# -- 7. Print next steps ------------------------------------------------------
Write-Host ""
Write-Host "Setup complete. Open a NEW terminal (so VCPKG_ROOT is visible) and run:"
Write-Host ""
Write-Host "  cmake --preset windows-vcpkg"
Write-Host "  cmake --build build --preset windows-vcpkg-release"
Write-Host ""
Write-Host "If cmake was previously run and failed, delete the build/ directory first:"
Write-Host "  Remove-Item -Recurse -Force build"
Write-Host ""
Write-Host "To run the test executable afterwards:"
Write-Host "  set GDAL_DATA=$VcpkgRoot\installed\x64-windows\share\gdal"
Write-Host "  build\Release\test_bathymetry.exe"
