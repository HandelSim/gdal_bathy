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

Dependencies (GDAL, HDF5, PROJ, ...) are fetched automatically via **vcpkg**.
You need Git and Visual Studio 2022 with the C++ workload installed.

### Step 1 — One-time bootstrap (PowerShell)

Run from the repository root in any PowerShell window:

```powershell
.\bootstrap-windows.ps1
```

This clones vcpkg to `C:\vcpkg`, builds the `vcpkg.exe` binary, and saves
`VCPKG_ROOT` as a permanent user environment variable.
It takes about a minute and only needs to be done once per machine.

### Step 2 — Configure and build

Open a **new** terminal (so `VCPKG_ROOT` is visible) and run:

```powershell
cmake --preset windows-vcpkg
cmake --build build --preset windows-vcpkg-release
```

On the first configure, vcpkg downloads and compiles GDAL plus all its
transitive dependencies (HDF5, PROJ, etc.). This takes **~10–20 minutes**
the first time; subsequent builds are instant because packages are cached.

### Step 3 — Run the test executable

```bat
set GDAL_DATA=C:\vcpkg\installed\x64-windows\share\gdal
build\Release\test_bathymetry.exe
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
| HDF5    | 1.10.x (Linux) / latest via vcpkg (Windows) | https://www.hdfgroup.org/ |
| PROJ    | 9.4.x (Linux) / latest via vcpkg (Windows) | https://proj.org |

## Repository Structure

```
bathymetry.h          <- public C++17 header (no GDAL/GSF types exposed)
bathymetry.cpp        <- implementation
CMakeLists.txt
CMakePresets.json     <- build presets (windows-vcpkg, linux-release)
vcpkg.json            <- vcpkg dependency manifest (Windows)
bootstrap-windows.ps1 <- one-time Windows setup script
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
