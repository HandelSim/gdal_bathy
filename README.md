# Bathymetry File Conversion Library

A self-contained C++17 library for reading and converting bathymetry files between BAG, GeoTIFF, XYZ and GSF formats.

## Public API

Three functions in namespace `bathy`:

```cpp
#include "bathymetry.h"

// 1. Query file metadata
bathy::FileInfo info = bathy::queryFile("survey.bag");
std::cout << info.raster.width << "x" << info.raster.height << "\n";
std::cout << info.raster.crsWkt << "\n";

// 2. Convert between formats
bathy::ConvertOptions opts;
opts.targetFormat    = bathy::Format::GeoTIFF;
opts.tiffCompression = "DEFLATE";
opts.assumedEpsg     = 4326;   // used when source BAG has no CRS
bathy::convertFile("survey.bag", "output.tif", opts);

// 3. Version string
std::string v = bathy::version();  // e.g. "bathymetry/1.0 gdal/3.12.2 gsf/03.11"
```

Supported conversions:

| Source   | Target   | Notes |
|----------|----------|-------|
| BAG      | GeoTIFF  | DEFLATE/LZW, tiled |
| BAG      | XYZ      | space-separated lon lat depth |
| GeoTIFF  | BAG      | via GDAL BAG driver |
| GeoTIFF  | XYZ      | first band only |
| XYZ      | GeoTIFF  | |
| XYZ      | BAG      | via GDAL BAG driver |
| GSF      | GeoTIFF  | nearest-neighbour binning |
| GSF      | XYZ      | one line per valid beam |
| Any raster | GSF   | one ping per row |

## Linux Build and Test

```bash
# Configure and build
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# Run tests (set GDAL_DATA and LD_LIBRARY_PATH)
LD_LIBRARY_PATH=deps/gdal/lib \
GDAL_DATA=deps/gdal/share/gdal \
./build/test_bathymetry
```

## Windows MSVC Build

> **Run all commands in `cmd.exe` or PowerShell, not Git Bash.**
> The `^` line-continuation character is CMD syntax; use `` ` `` in PowerShell.

### Step 1 — Get pre-built Windows dependencies

The `windows-deps/` subdirectory contains `README.txt` files for each library
explaining where to download binaries.  Follow them in order:

| Directory | What's needed |
|-----------|---------------|
| `windows-deps/gdal/` | `gdal_i.lib` + DLLs + headers (see `README.txt`) |
| `windows-deps/hdf5/` | HDF5 1.14.6 MSVC binaries (see `README.txt`) |
| `windows-deps/proj/` | PROJ 9.x MSVC binaries (see `README.txt`) |

The fastest path is **vcpkg** — it handles GDAL and all its transitive
dependencies in one command:

```bat
vcpkg install gdal:x64-windows
```

Then pass the vcpkg toolchain file to CMake (Step 2 below).

### Step 2 — Configure and build

**Option A — vcpkg (recommended)**

```bat
cmake -S . -B build ^
  -G "Visual Studio 17 2022" -A x64 ^
  -DCMAKE_TOOLCHAIN_FILE=C:\vcpkg\scripts\buildsystems\vcpkg.cmake

cmake --build build --config Release
```

**Option B — manually placed binaries in `windows-deps/`**

```bat
cmake -S . -B build ^
  -G "Visual Studio 17 2022" -A x64 ^
  -DGDAL_ROOT="%CD%\windows-deps\gdal" ^
  -DHDF5_ROOT="%CD%\windows-deps\hdf5" ^
  -DPROJ_ROOT="%CD%\windows-deps\proj"

cmake --build build --config Release
```

### Step 3 — Set PATH before running the executable

```bat
set PATH=%CD%\windows-deps\gdal\bin;%CD%\windows-deps\hdf5\bin;%CD%\windows-deps\proj\bin;%PATH%
set GDAL_DATA=%CD%\deps\gdal\share\gdal
```

## BAG Test File Coverage

| File | Version | Dims | VR | CRS |
|------|---------|------|-----|-----|
| synth_v100_no_crs.bag | 1.0.0 | 20x20 | no | None (synthetic, no CRS in metadata) |
| synth_v101_geographic.bag | 1.0.1 | 20x20 | no | EPSG:4326 WGS84 geographic |
| synth_v110_utm.bag | 1.1.0 | 20x20 | no | EPSG:32618 UTM-18N projected |
| synth_v151_nominal.bag | 1.5.1 | 20x20 | no | EPSG:4326 with nominal_elevation layer |
| synth_v200_projected.bag | 2.0.0 | 20x20 | no | EPSG:26918 NAD83 UTM-18N |
| sample.bag | 2.0.1 | 100x100 | no | WGS84 |
| sample-1.5.0.bag | 1.5.0 | 100x100 | no | WGS84 |
| sample-2.0.1.bag | 2.0.1 | 100x100 | no | WGS84 |
| nominal_only.bag | 1.1.0 | 10x10 | no | WGS84 |
| true_n_nominal.bag | 1.1.0 | 10x10 | no | WGS84 (True North) |
| southern_hemi_false_northing.bag | 1.4.0 | 52x71 | no | Projected (false northing) |
| example_w_qc_layers.bag | 1.5.1 | 1008x1218 | no | WGS84 + QC layers |
| bag_163_vr.bag | 1.6.3 | 529x579 | YES | WGS84 variable-resolution |
| Sample_VR_BAG-gzip.bag | 1.6.0 | 4x4 | YES | VR gzip-compressed |
| test_vr.bag | 1.6.2 | 4x6 | YES | VR test |
| test_offset_ne_corner.bag | 1.6.2 | 4x6 | YES | NE corner offset |
| test_interpolated.bag | 2.0.0 | 4x6 | YES | interpolated depths |
| test_georef_metadata.bag | 2.0.0 | 4x6 | YES | georef metadata layer |
| metadata_layer_example.bag | 2.0.0 | 100x100 | YES | metadata layers |
| bag_georefmetadata_layer.bag | 2.0.1 | 100x100 | no | georef metadata |

Real BAG files sourced from [GDAL autotest suite](https://github.com/OSGeo/gdal) and
[OpenNavigationSurface BAG library](https://github.com/OpenNavigationSurface/BAG).

## Dependency Versions

| Library | Version | Source |
|---------|---------|--------|
| GDAL    | 3.12.2  | https://gdal.org (built from source, BAG+GTiff+XYZ only) |
| GSF     | 03.11   | https://leidos.com (Leidos Generic Sensor Format) |
| HDF5    | 1.10.x (Linux) / 1.14.6 (Windows) | https://www.hdfgroup.org/ |
| PROJ    | 9.4.x (Linux) / 9.x (Windows) | https://proj.org / OSGeo4W |

## Repository Structure

```
bathymetry.h          <- public C++17 header (no GDAL/GSF types exposed)
bathymetry.cpp        <- implementation
CMakeLists.txt
README.md
.gitignore
test/
  test_bathymetry.cpp
  data/
    bag/              <- 22 BAG test files (real + synthetic)
    gsf/              <- GSF test files
    tif/              <- synthetic GeoTIFF
    xyz/              <- synthetic XYZ
deps/
  gdal/
    include/          <- all GDAL public headers
    lib/              <- libgdal.so (Linux) / gdal_i.lib (Windows)
    bin/              <- gdal-config
    share/gdal/       <- GDAL data files (projections, etc.)
  gsf/
    src/              <- Leidos GSF C source files
    CMakeLists.txt
    include/gsf/      <- GSF headers
    lib/              <- libgsf.a
windows-deps/
  README.md
  gdal/               <- GDAL Windows MSVC binaries (or README.txt with download instructions)
  hdf5/               <- HDF5 1.14.6 Windows MSVC binaries (or README.txt)
  proj/               <- PROJ 9.x Windows MSVC binaries (or README.txt)
```
