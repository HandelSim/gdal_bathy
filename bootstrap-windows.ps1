<#
.SYNOPSIS
    One-time setup: installs vcpkg and records VCPKG_ROOT so CMake can find it.

.DESCRIPTION
    Run this once from any PowerShell window before your first build.
    It does NOT require Administrator privileges.

    What it does:
      1. Clones vcpkg to C:\vcpkg (override with -VcpkgRoot)
      2. Bootstraps the vcpkg executable
      3. Persists VCPKG_ROOT as a user environment variable

    After this script finishes, open a new terminal and run:
      cmake --preset windows-vcpkg
      cmake --build build --preset windows-vcpkg-release

    On first configure, vcpkg will automatically download and build GDAL
    (+ HDF5, PROJ, and all other transitive dependencies) from the vcpkg.json
    in this repository. This takes ~10-20 minutes the first time; subsequent
    builds reuse the cached packages.

.PARAMETER VcpkgRoot
    Where to install vcpkg. Defaults to C:\vcpkg.
#>
param(
    [string]$VcpkgRoot = "C:\vcpkg"
)

$ErrorActionPreference = "Stop"

# -- 1. Clone vcpkg if not already present ------------------------------------
if (-not (Test-Path "$VcpkgRoot\vcpkg.exe")) {
    if (-not (Test-Path $VcpkgRoot)) {
        Write-Host "Cloning vcpkg to $VcpkgRoot ..."
        git clone https://github.com/microsoft/vcpkg.git $VcpkgRoot
    } else {
        Write-Host "vcpkg directory exists but vcpkg.exe is missing - bootstrapping ..."
    }
    Write-Host "Bootstrapping vcpkg ..."
    & "$VcpkgRoot\bootstrap-vcpkg.bat" -disableMetrics
} else {
    Write-Host "vcpkg already present at $VcpkgRoot"
}

# -- 2. Persist VCPKG_ROOT for the current user -------------------------------
[System.Environment]::SetEnvironmentVariable("VCPKG_ROOT", $VcpkgRoot, "User")
$env:VCPKG_ROOT = $VcpkgRoot
Write-Host "VCPKG_ROOT set to $VcpkgRoot (user environment, permanent)"

# -- 3. Print next steps ------------------------------------------------------
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
