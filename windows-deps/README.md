# Windows MSVC Pre-Built Dependencies

These binaries are for building the bathymetry library on **Windows x64 with MSVC**.
They are NOT used by the Linux build or tests.

## Contents

```
windows-deps/
    hdf5/
        include/     <- HDF5 C headers (hdf5.h etc.)
        lib/         <- hdf5.lib, hdf5_hl.lib  (MSVC import libraries)
        bin/         <- hdf5.dll, hdf5_hl.dll, szip.dll, zlib.dll
        cmake/       <- HDF5Config.cmake
    proj/
        include/     <- proj.h
        lib/         <- proj.lib
        bin/         <- proj_9*.dll
        share/proj/  <- proj.db datum database
```

## Versions

| Library | Version | Source |
|---------|---------|--------|
| HDF5    | 1.14.6  | https://www.hdfgroup.org/download-hdf5/ |
| PROJ    | 9.x     | https://proj.org / OSGeo4W              |

## How to use on Windows

Point CMake at both directories:

```bat
cmake -S . -B build ^
  -G "Visual Studio 17 2022" -A x64 ^
  -DHDF5_ROOT="%CD%\windows-deps\hdf5" ^
  -DPROJ_ROOT="%CD%\windows-deps\proj" ^
  -DCMAKE_PREFIX_PATH="%CD%\windows-deps\hdf5;%CD%\windows-deps\proj"
```

Add to PATH before running the executable:

```bat
set PATH=%CD%\windows-deps\hdf5\bin;%CD%\windows-deps\proj\bin;%PATH%
```

## If binaries are missing

If either subdirectory contains only a README.txt, the automated download
failed at build time. Follow the instructions in that README.txt to obtain
and place the binaries manually.
