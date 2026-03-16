GDAL Windows x64 MSVC binaries are not included in the repository.

You need: gdal_i.lib (import library) + gdal*.dll + headers.
The easiest ways to obtain them are listed below.

----------------------------------------------------------------------
Option 1 — vcpkg (recommended, integrates with CMake automatically)
----------------------------------------------------------------------
  vcpkg install gdal:x64-windows

  Then pass the toolchain file to CMake instead of -DGDAL_ROOT:
    cmake -S . -B build ^
      -G "Visual Studio 17 2022" -A x64 ^
      -DCMAKE_TOOLCHAIN_FILE=C:\vcpkg\scripts\buildsystems\vcpkg.cmake ^
      -DHDF5_ROOT="%CD%\windows-deps\hdf5" ^
      -DPROJ_ROOT="%CD%\windows-deps\proj"

  vcpkg will supply GDAL and its transitive dependencies automatically.

----------------------------------------------------------------------
Option 2 — OSGeo4W installer
----------------------------------------------------------------------
  1. Download https://download.osgeo.org/osgeo4w/v2/osgeo4w-setup.exe
  2. Install packages: gdal, gdal-devel
  3. Copy from C:\OSGeo4W\ into this directory so it looks like:
       windows-deps\gdal\
           include\      <- gdal.h, cpl_conv.h, ogr_api.h, etc.
           lib\          <- gdal_i.lib
           bin\          <- gdal*.dll (and its dependency DLLs)
  4. Then run CMake with -DGDAL_ROOT="%CD%\windows-deps\gdal"

----------------------------------------------------------------------
Option 3 — GISInternals pre-built SDK (standalone, no installer)
----------------------------------------------------------------------
  1. Go to https://www.gisinternals.com/release.php
  2. Download the "release-1930-x64-gdal-3-X-X-mapserver-8-X-X.zip" SDK
     matching Visual Studio 2022 / x64.
  3. Extract so this directory contains:
       windows-deps\gdal\
           include\      <- GDAL headers
           lib\          <- gdal_i.lib
           bin\          <- gdal*.dll + dependency DLLs
  4. Then run CMake with -DGDAL_ROOT="%CD%\windows-deps\gdal"

----------------------------------------------------------------------
CMake invocation after placing binaries here (Options 2 or 3)
----------------------------------------------------------------------
  cmake -S . -B build ^
    -G "Visual Studio 17 2022" -A x64 ^
    -DGDAL_ROOT="%CD%\windows-deps\gdal" ^
    -DHDF5_ROOT="%CD%\windows-deps\hdf5" ^
    -DPROJ_ROOT="%CD%\windows-deps\proj"

  cmake --build build --config Release

  Before running the executable, add the DLL directories to PATH:
    set PATH=%CD%\windows-deps\gdal\bin;%CD%\windows-deps\hdf5\bin;%CD%\windows-deps\proj\bin;%PATH%
    set GDAL_DATA=%CD%\deps\gdal\share\gdal

----------------------------------------------------------------------
NOTE: run these commands in a Command Prompt (cmd.exe) or PowerShell,
      NOT in Git Bash. The ^ line-continuation character is CMD syntax.
      In PowerShell use a backtick ` instead of ^.
----------------------------------------------------------------------
