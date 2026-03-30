// bathymetry.cpp — implementation of bathymetry conversion library
// Requires: GDAL 3.x (with BAG/GTiff/XYZ drivers) + Leidos GSF 03.11
// Target: C++17, Windows MSVC x64 / Linux GCC

#include "bathymetry.h"

// GDAL headers
#include "gdal.h"
#include "gdal_priv.h"
#include "cpl_conv.h"
#include "ogr_spatialref.h"

// GSF headers
#include "gsf.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace bathy {

// ---------------------------------------------------------------------------
// RAII wrapper for GDALDataset — never call delete on GDALDataset
// ---------------------------------------------------------------------------
struct GdalDatasetDeleter {
    void operator()(GDALDataset* ds) const noexcept {
        if (ds) GDALClose(ds);
    }
};
using DatasetPtr = std::unique_ptr<GDALDataset, GdalDatasetDeleter>;

// ---------------------------------------------------------------------------
// One-time GDAL initialisation
// ---------------------------------------------------------------------------
static void EnsureGdalInit() {
    static bool done = false;
    if (!done) {
        GDALAllRegister();
        done = true;
    }
}

// ---------------------------------------------------------------------------
// Format detection — magic bytes first, extension fallback
// ---------------------------------------------------------------------------
static Format DetectFormat(const std::filesystem::path& path) {
    // Read first 8 bytes for magic detection
    std::ifstream f(path, std::ios::binary);
    unsigned char magic[8] = {};
    if (f.is_open()) {
        f.read(reinterpret_cast<char*>(magic), 8);
    }

    // HDF5 magic: 89 48 44 46 0D 0A 1A 0A
    if (magic[0]==0x89 && magic[1]==0x48 && magic[2]==0x44 && magic[3]==0x46 &&
        magic[4]==0x0D && magic[5]==0x0A && magic[6]==0x1A && magic[7]==0x0A) {
        // Could be HDF5/BAG — use extension to disambiguate
        auto ext = path.extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(),
                       [](unsigned char c) { return (char)::tolower(c); });
        if (ext == ".bag") return Format::BAG;
        // Other HDF5-based formats fall through to GeoTIFF (they won't be)
        return Format::BAG; // default HDF5 to BAG for our purposes
    }

    // TIFF little-endian: 49 49 2A 00
    if (magic[0]==0x49 && magic[1]==0x49 && magic[2]==0x2A && magic[3]==0x00)
        return Format::GeoTIFF;
    // TIFF big-endian: 4D 4D 00 2A
    if (magic[0]==0x4D && magic[1]==0x4D && magic[2]==0x00 && magic[3]==0x2A)
        return Format::GeoTIFF;
    // BigTIFF little-endian: 49 49 2B 00
    if (magic[0]==0x49 && magic[1]==0x49 && magic[2]==0x2B && magic[3]==0x00)
        return Format::GeoTIFF;

    // Extension fallback
    auto ext = path.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(),
                   [](unsigned char c) { return (char)::tolower(c); });

    if (ext == ".bag")  return Format::BAG;
    if (ext == ".tif" || ext == ".tiff") return Format::GeoTIFF;
    if (ext == ".gsf")  return Format::GSF;
    if (ext == ".xyz" || ext == ".txt" || ext == ".csv") return Format::XYZ;

    return Format::Unknown;
}

// ---------------------------------------------------------------------------
// Helper: read raster info from an open GDALDataset
// ---------------------------------------------------------------------------
static RasterInfo RasterInfoFromDataset(GDALDataset* ds) {
    RasterInfo ri;
    ri.width     = ds->GetRasterXSize();
    ri.height    = ds->GetRasterYSize();
    ri.bandCount = ds->GetRasterCount();

    double gt[6] = {};
    if (ds->GetGeoTransform(gt) == CE_None) {
        ri.originX    = gt[0];
        ri.originY    = gt[3];
        ri.pixelSizeX = gt[1];
        ri.pixelSizeY = gt[5];
    }

    const char* wkt = ds->GetProjectionRef();
    if (wkt && wkt[0] != '\0') {
        ri.crsWkt = wkt;
    }

    if (ds->GetRasterCount() > 0) {
        GDALRasterBand* band = ds->GetRasterBand(1);
        int hasNd = 0;
        double nd = band->GetNoDataValue(&hasNd);
        ri.hasNoData   = (hasNd != 0);
        ri.noDataValue = nd;
    }

    return ri;
}

// ---------------------------------------------------------------------------
// queryFile
// ---------------------------------------------------------------------------
FileInfo QueryFile(const std::filesystem::path& inputPath) {
    EnsureGdalInit();

    FileInfo fi;
    fi.format = DetectFormat(inputPath);

    if (fi.format == Format::GSF) {
        // Read GSF pings
        int handle = -1;
        if (gsfOpen(inputPath.string().c_str(), GSF_READONLY, &handle) < 0) {
            throw std::runtime_error("queryFile: cannot open GSF file: " +
                                     inputPath.string());
        }

        gsfRecords rec;
        gsfDataID  id;
        memset(&rec, 0, sizeof(rec));
        memset(&id,  0, sizeof(id));

        int pingCount = 0;
        const int kMaxPings = 10000;
        bool collectPings = true;

        while (true) {
            int bytes = gsfRead(handle, GSF_NEXT_RECORD, &id, &rec, nullptr, 0);
            if (bytes <= 0) break;
            if (id.recordID == GSF_RECORD_SWATH_BATHYMETRY_PING) {
                ++pingCount;
                if (collectPings && pingCount <= kMaxPings) {
                    GsfPingInfo pi;
                    pi.latitude  = rec.mb_ping.latitude;
                    pi.longitude = rec.mb_ping.longitude;
                    pi.beamCount = rec.mb_ping.number_beams;

                    if (rec.mb_ping.depth && rec.mb_ping.number_beams > 0) {
                        double mn = rec.mb_ping.depth[0];
                        double mx = rec.mb_ping.depth[0];
                        for (int b = 1; b < rec.mb_ping.number_beams; ++b) {
                            mn = std::min(mn, rec.mb_ping.depth[b]);
                            mx = std::max(mx, rec.mb_ping.depth[b]);
                        }
                        pi.depthMin = mn;
                        pi.depthMax = mx;
                    }
                    fi.gsf.pings.push_back(pi);
                } else if (pingCount > kMaxPings) {
                    collectPings = false;
                    fi.gsf.pings.clear();
                }
            }
        }
        gsfClose(handle);
        fi.gsf.pingCount = pingCount;
        return fi;
    }

    // For raster formats, use GDAL
    std::string openPath = inputPath.string();

    // XYZ special: ensure we open via GDAL
    GDALDataset* rawDs = nullptr;
    if (fi.format == Format::BAG) {
        rawDs = static_cast<GDALDataset*>(
            GDALOpenEx(openPath.c_str(), GDAL_OF_RASTER | GDAL_OF_READONLY,
                       nullptr, nullptr, nullptr));
    } else {
        rawDs = static_cast<GDALDataset*>(
            GDALOpen(openPath.c_str(), GA_ReadOnly));
    }

    if (!rawDs) {
        throw std::runtime_error("queryFile: GDAL cannot open: " +
                                 inputPath.string() +
                                 " (" + CPLGetLastErrorMsg() + ")");
    }
    DatasetPtr ds(rawDs);

    fi.raster = RasterInfoFromDataset(ds.get());
    return fi;
}

// ---------------------------------------------------------------------------
// Helper: apply assumed CRS to a dataset when source has none
// ---------------------------------------------------------------------------
static void ApplyCrs(GDALDataset* ds, int epsg) {
    OGRSpatialReference srs;
    srs.importFromEPSG(epsg);
    srs.SetAxisMappingStrategy(OAMS_TRADITIONAL_GIS_ORDER);
    ds->SetSpatialRef(&srs);
    fprintf(stderr, "[bathy] BAG file has no CRS — assuming EPSG:%d\n", epsg);
}

// ---------------------------------------------------------------------------
// Post-conversion validation (raster-to-raster)
// ---------------------------------------------------------------------------
static void ValidateRasterMatch(GDALDataset* src, GDALDataset* dst,
                                 bool strict, const std::filesystem::path& dstPath) {
    if (!strict) return;

    // 1. Dimensions
    if (src->GetRasterXSize() != dst->GetRasterXSize() ||
        src->GetRasterYSize() != dst->GetRasterYSize()) {
        std::filesystem::remove(dstPath);
        throw std::runtime_error(
            "Validation failed: dimension mismatch. src=" +
            std::to_string(src->GetRasterXSize()) + "x" +
            std::to_string(src->GetRasterYSize()) + " dst=" +
            std::to_string(dst->GetRasterXSize()) + "x" +
            std::to_string(dst->GetRasterYSize()));
    }

    // 2. GeoTransform
    double srcGt[6] = {}, dstGt[6] = {};
    bool hasSrcGt = (src->GetGeoTransform(srcGt) == CE_None);
    bool hasDstGt = (dst->GetGeoTransform(dstGt) == CE_None);

    if (hasSrcGt && hasDstGt) {
        if (std::abs(srcGt[0] - dstGt[0]) > 1e-10 ||
            std::abs(srcGt[3] - dstGt[3]) > 1e-10) {
            std::filesystem::remove(dstPath);
            throw std::runtime_error(
                "Validation failed: GeoTransform origin mismatch");
        }
        // 3. Pixel size relative tolerance
        if (srcGt[1] != 0.0) {
            double relX = std::abs(srcGt[1] - dstGt[1]) / std::abs(srcGt[1]);
            if (relX > 1e-8) {
                std::filesystem::remove(dstPath);
                throw std::runtime_error(
                    "Validation failed: pixel size X mismatch");
            }
        }
        if (srcGt[5] != 0.0) {
            double relY = std::abs(srcGt[5] - dstGt[5]) / std::abs(srcGt[5]);
            if (relY > 1e-8) {
                std::filesystem::remove(dstPath);
                throw std::runtime_error(
                    "Validation failed: pixel size Y mismatch");
            }
        }
    }

    // 4. CRS check
    const char* srcWkt = src->GetProjectionRef();
    const char* dstWkt = dst->GetProjectionRef();
    bool srcHasCrs = srcWkt && srcWkt[0] != '\0';
    bool dstHasCrs = dstWkt && dstWkt[0] != '\0';

    if (srcHasCrs && dstHasCrs) {
        OGRSpatialReference srcSrs, dstSrs;
        if (srcSrs.importFromWkt(srcWkt) == OGRERR_NONE &&
            dstSrs.importFromWkt(dstWkt) == OGRERR_NONE) {
            srcSrs.SetAxisMappingStrategy(OAMS_TRADITIONAL_GIS_ORDER);
            dstSrs.SetAxisMappingStrategy(OAMS_TRADITIONAL_GIS_ORDER);
            if (!srcSrs.IsSame(&dstSrs)) {
                std::filesystem::remove(dstPath);
                throw std::runtime_error(
                    "Validation failed: CRS mismatch between source and destination");
            }
        }
    }

    // 5. NoData
    if (src->GetRasterCount() > 0 && dst->GetRasterCount() > 0) {
        int srcHasNd = 0, dstHasNd = 0;
        double srcNd = src->GetRasterBand(1)->GetNoDataValue(&srcHasNd);
        double dstNd = dst->GetRasterBand(1)->GetNoDataValue(&dstHasNd);
        if (srcHasNd && dstHasNd) {
            bool srcNan = std::isnan(srcNd);
            bool dstNan = std::isnan(dstNd);
            if (srcNan != dstNan || (!srcNan && !dstNan && srcNd != dstNd)) {
                std::filesystem::remove(dstPath);
                throw std::runtime_error(
                    "Validation failed: NoData value mismatch");
            }
        }
    }
}

// ---------------------------------------------------------------------------
// GSF → raster helpers
// ---------------------------------------------------------------------------
static void GsfToGeoTiff(const std::filesystem::path& input,
                          const std::filesystem::path& output,
                          const ConvertOptions& /*opts*/) {
    EnsureGdalInit();

    int handle = -1;
    if (gsfOpen(input.string().c_str(), GSF_READONLY, &handle) < 0) {
        throw std::runtime_error("GsfToGeoTiff: cannot open GSF: " +
                                 input.string());
    }

    // Collect all valid pings
    struct Ping { double lon, lat, depth; };
    std::vector<Ping> pings;

    gsfRecords rec;
    gsfDataID  id;
    memset(&rec, 0, sizeof(rec));
    memset(&id,  0, sizeof(id));

    double minLon= 1e18, maxLon=-1e18, minLat= 1e18, maxLat=-1e18;

    while (true) {
        int bytes = gsfRead(handle, GSF_NEXT_RECORD, &id, &rec, nullptr, 0);
        if (bytes <= 0) break;
        if (id.recordID != GSF_RECORD_SWATH_BATHYMETRY_PING) continue;

        double lon = rec.mb_ping.longitude;
        double lat = rec.mb_ping.latitude;
        if (!rec.mb_ping.depth) continue;

        for (int b = 0; b < rec.mb_ping.number_beams; ++b) {
            double d = rec.mb_ping.depth[b];
            if (d <= 0.0 || std::isnan(d)) continue;
            pings.push_back({lon, lat, d});
            minLon = std::min(minLon, lon);
            maxLon = std::max(maxLon, lon);
            minLat = std::min(minLat, lat);
            maxLat = std::max(maxLat, lat);
        }
    }
    gsfClose(handle);

    if (pings.empty()) {
        throw std::runtime_error("GsfToGeoTiff: no valid depth data in GSF file");
    }

    // Create a regular grid (nearest-neighbour)
    const int kCols = 100, kRows = 100;
    double pixX = (maxLon - minLon) / kCols;
    double pixY = (maxLat - minLat) / kRows;
    if (pixX <= 0) pixX = 0.001;
    if (pixY <= 0) pixY = 0.001;

    std::vector<float> grid(kCols * kRows, static_cast<float>(-9999.0));

    for (auto& p : pings) {
        int col = static_cast<int>((p.lon - minLon) / pixX);
        int row = static_cast<int>((maxLat - p.lat) / pixY);
        col = std::max(0, std::min(kCols-1, col));
        row = std::max(0, std::min(kRows-1, row));
        grid[row * kCols + col] = static_cast<float>(-p.depth); // depth→negative elevation
    }

    GDALDriverH drv = GDALGetDriverByName("GTiff");
    const char* copts[] = {"COMPRESS=DEFLATE", "TILED=YES",
                            "BLOCKXSIZE=256", "BLOCKYSIZE=256", nullptr};
    GDALDatasetH ds = GDALCreate(drv, output.string().c_str(),
                                  kCols, kRows, 1, GDT_Float32,
                                  const_cast<char**>(copts));
    if (!ds) {
        throw std::runtime_error("GsfToGeoTiff: cannot create output: " +
                                 output.string());
    }

    double gt[6] = {minLon, pixX, 0, maxLat, 0, -pixY};
    GDALSetGeoTransform(ds, gt);

    OGRSpatialReference srs;
    srs.importFromEPSG(4326);
    srs.SetAxisMappingStrategy(OAMS_TRADITIONAL_GIS_ORDER);
    char* wkt = nullptr;
    srs.exportToWkt(&wkt);
    GDALSetProjection(ds, wkt);
    CPLFree(wkt);

    GDALRasterBandH band = GDALGetRasterBand(ds, 1);
    GDALSetRasterNoDataValue(band, -9999.0);
    GDALRasterIO(band, GF_Write, 0, 0, kCols, kRows,
                 grid.data(), kCols, kRows, GDT_Float32, 0, 0);
    GDALClose(ds);
}

static void GsfToXyz(const std::filesystem::path& input,
                      const std::filesystem::path& output,
                      const ConvertOptions& opts) {
    int handle = -1;
    if (gsfOpen(input.string().c_str(), GSF_READONLY, &handle) < 0) {
        throw std::runtime_error("GsfToXyz: cannot open GSF: " + input.string());
    }

    std::ofstream out(output);
    if (!out) {
        gsfClose(handle);
        throw std::runtime_error("GsfToXyz: cannot create output: " + output.string());
    }

    gsfRecords rec;
    gsfDataID  id;
    memset(&rec, 0, sizeof(rec));
    memset(&id,  0, sizeof(id));
    char sep = opts.xyzSeparator;

    while (true) {
        int bytes = gsfRead(handle, GSF_NEXT_RECORD, &id, &rec, nullptr, 0);
        if (bytes <= 0) break;
        if (id.recordID != GSF_RECORD_SWATH_BATHYMETRY_PING) continue;
        if (!rec.mb_ping.depth) continue;

        double lon = rec.mb_ping.longitude;
        double lat = rec.mb_ping.latitude;

        for (int b = 0; b < rec.mb_ping.number_beams; ++b) {
            double d = rec.mb_ping.depth[b];
            if (d <= 0.0 || std::isnan(d)) continue;
            out << std::fixed << std::setprecision(6)
                << lon << sep << lat << sep
                << std::setprecision(4) << (-d) << '\n';
        }
    }
    gsfClose(handle);
}

// ---------------------------------------------------------------------------
// Raster → GSF
// ---------------------------------------------------------------------------
static void RasterToGsf(const std::filesystem::path& input,
                         const std::filesystem::path& output) {
    EnsureGdalInit();

    GDALDataset* rawDs = static_cast<GDALDataset*>(
        GDALOpen(input.string().c_str(), GA_ReadOnly));
    if (!rawDs) {
        throw std::runtime_error("RasterToGsf: cannot open: " + input.string());
    }
    DatasetPtr ds(rawDs);

    int cols = ds->GetRasterXSize();
    int rows = ds->GetRasterYSize();
    double gt[6] = {};
    ds->GetGeoTransform(gt);

    GDALRasterBand* band = ds->GetRasterBand(1);
    int hasNd = 0;
    double nd = band->GetNoDataValue(&hasNd);

    int handle = -1;
    if (gsfOpen(output.string().c_str(), GSF_CREATE, &handle) < 0) {
        throw std::runtime_error("RasterToGsf: cannot create GSF: " + output.string());
    }

    std::vector<double> depths(cols), across(cols);
    gsfRecords rec;
    gsfDataID  id;
    memset(&rec, 0, sizeof(rec));
    memset(&id,  0, sizeof(id));
    id.recordID = GSF_RECORD_SWATH_BATHYMETRY_PING;

    std::vector<float> rowBuf(cols);

    for (int r = 0; r < rows; ++r) {
        band->RasterIO(GF_Read, 0, r, cols, 1,
                       rowBuf.data(), cols, 1, GDT_Float32, 0, 0);

        rec.mb_ping.latitude  = gt[3] + (r + 0.5) * gt[5];
        rec.mb_ping.longitude = gt[0] + (cols * 0.5) * gt[1];
        rec.mb_ping.number_beams = static_cast<short>(cols);
        rec.mb_ping.depth       = depths.data();
        rec.mb_ping.across_track= across.data();

        for (int c = 0; c < cols; ++c) {
            float v = rowBuf[c];
            if (hasNd && v == static_cast<float>(nd)) {
                depths[c] = 0.0;
            } else {
                depths[c] = -static_cast<double>(v); // elevation→depth
            }
            across[c] = (c - cols / 2.0) * std::abs(gt[1]) * 111320.0; // approx metres
        }
        gsfWrite(handle, &id, &rec);
    }
    gsfClose(handle);
}

// ---------------------------------------------------------------------------
// convertFile — main entry point
// ---------------------------------------------------------------------------
void ConvertFile(const std::filesystem::path& inputPath,
                 const std::filesystem::path& outputPath,
                 const ConvertOptions& opts) {
    EnsureGdalInit();

    Format srcFormat = DetectFormat(inputPath);

    // GSF → raster
    if (srcFormat == Format::GSF) {
        if (opts.targetFormat == Format::GeoTIFF) {
            GsfToGeoTiff(inputPath, outputPath, opts);
        } else if (opts.targetFormat == Format::XYZ) {
            GsfToXyz(inputPath, outputPath, opts);
        } else {
            throw std::runtime_error(
                "convertFile: unsupported conversion from GSF to target format");
        }
        return;
    }

    // Raster → GSF
    if (opts.targetFormat == Format::GSF) {
        RasterToGsf(inputPath, outputPath);
        return;
    }

    // Raster → XYZ (text output — use GDAL XYZ driver via GDALCreateCopy)
    // Raster → Raster via GDAL

    // Open source dataset
    std::string srcPath = inputPath.string();
    GDALDataset* rawSrc = nullptr;

    if (srcFormat == Format::BAG) {
        // Handle BAG mode
        if (opts.bagMode == "LOW_RES" || opts.bagMode.empty()) {
            rawSrc = static_cast<GDALDataset*>(
                GDALOpenEx(srcPath.c_str(), GDAL_OF_RASTER | GDAL_OF_READONLY,
                           nullptr, nullptr, nullptr));
        } else if (opts.bagMode.substr(0, 9) == "SUPERGRID") {
            // Format: SUPERGRID:y:x
            std::string sub = "BAG:\"" + srcPath + "\":" +
                opts.bagMode.substr(0, 9) + ":" +
                opts.bagMode.substr(10); // rest is y:x
            rawSrc = static_cast<GDALDataset*>(
                GDALOpen(sub.c_str(), GA_ReadOnly));
        } else if (opts.bagMode.substr(0, 9) == "RESAMPLED") {
            // Format: RESAMPLED:xres:yres
            std::string resStr = opts.bagMode.substr(10);
            auto colon = resStr.find(':');
            std::string xres = resStr.substr(0, colon);
            std::string yres = resStr.substr(colon + 1);
            const char* openOpts[] = {
                "MODE=RESAMPLED_GRID",
                ("RESX=" + xres).c_str(),
                ("RESY=" + yres).c_str(),
                nullptr
            };
            rawSrc = static_cast<GDALDataset*>(
                GDALOpenEx(srcPath.c_str(),
                           GDAL_OF_RASTER | GDAL_OF_READONLY,
                           nullptr, openOpts, nullptr));
        }
    } else {
        rawSrc = static_cast<GDALDataset*>(
            GDALOpen(srcPath.c_str(), GA_ReadOnly));
    }

    if (!rawSrc) {
        throw std::runtime_error(
            "convertFile: cannot open source: " + srcPath +
            " (" + CPLGetLastErrorMsg() + ")");
    }
    DatasetPtr src(rawSrc);

    // Detect if source BAG has no CRS and apply assumed EPSG
    bool srcNoCrs = false;
    if (srcFormat == Format::BAG) {
        const char* wkt = src->GetProjectionRef();
        if (!wkt || wkt[0] == '\0') {
            srcNoCrs = true;
            ApplyCrs(src.get(), opts.assumedEpsg);
        }
    }

    // Determine output driver name and creation options
    std::string driverName;
    std::vector<std::string> coStrings;
    std::vector<const char*> coList;

    switch (opts.targetFormat) {
        case Format::GeoTIFF:
            driverName = "GTiff";
            coStrings = {
                "COMPRESS=" + opts.tiffCompression,
                "PREDICTOR=3",
                "TILED=YES",
                "BLOCKXSIZE=256",
                "BLOCKYSIZE=256"
            };
            break;
        case Format::BAG:
            driverName = "BAG";
            break;
        case Format::XYZ:
            driverName = "XYZ";
            break;
        default:
            throw std::runtime_error(
                "convertFile: unsupported target format");
    }

    for (auto& s : coStrings) coList.push_back(s.c_str());
    coList.push_back(nullptr);

    GDALDriverH drvH = GDALGetDriverByName(driverName.c_str());
    if (!drvH) {
        throw std::runtime_error(
            "convertFile: GDAL driver not found: " + driverName);
    }

    GDALDataset* rawDst = static_cast<GDALDataset*>(
        GDALCreateCopy(drvH, outputPath.string().c_str(),
                       src.get(),
                       FALSE, // strict
                       coStrings.empty() ? nullptr :
                           const_cast<char**>(coList.data()),
                       nullptr, nullptr));

    if (!rawDst) {
        throw std::runtime_error(
            "convertFile: GDALCreateCopy failed: " + outputPath.string() +
            " (" + CPLGetLastErrorMsg() + ")");
    }
    DatasetPtr dst(rawDst);

    // Apply assumed CRS to output if source had none
    if (srcNoCrs && opts.targetFormat != Format::XYZ) {
        OGRSpatialReference srs;
        srs.importFromEPSG(opts.assumedEpsg);
        srs.SetAxisMappingStrategy(OAMS_TRADITIONAL_GIS_ORDER);
        dst->SetSpatialRef(&srs);
    }

    // Post-conversion validation (raster-to-raster, skip XYZ target)
    if (opts.targetFormat != Format::XYZ && opts.targetFormat != Format::BAG) {
        ValidateRasterMatch(src.get(), dst.get(), opts.strictValidation, outputPath);
    }
}

// ---------------------------------------------------------------------------
// describeFile — human-readable file info (like gdalinfo)
// ---------------------------------------------------------------------------
static const char* FormatName(Format f) {
    switch (f) {
        case Format::BAG:     return "BAG (HDF5)";
        case Format::GeoTIFF: return "GeoTIFF";
        case Format::XYZ:     return "XYZ (ASCII grid)";
        case Format::GSF:     return "GSF (Generic Sensor Format)";
        default:              return "Unknown";
    }
}

std::string DescribeFile(const std::filesystem::path& inputPath) {
    FileInfo fi = QueryFile(inputPath);
    std::ostringstream os;

    os << "File:   " << inputPath.filename().string() << "\n";
    os << "Format: " << FormatName(fi.format) << "\n";

    if (fi.format == Format::GSF) {
        os << "Pings:  " << fi.gsf.pingCount << "\n";
        if (!fi.gsf.pings.empty()) {
            double minLat = 1e18, maxLat = -1e18;
            double minLon = 1e18, maxLon = -1e18;
            double minD = 1e18, maxD = -1e18;
            int totalBeams = 0;
            for (auto& p : fi.gsf.pings) {
                minLat = std::min(minLat, p.latitude);
                maxLat = std::max(maxLat, p.latitude);
                minLon = std::min(minLon, p.longitude);
                maxLon = std::max(maxLon, p.longitude);
                if (p.depthMin != 0.0 || p.depthMax != 0.0) {
                    minD = std::min(minD, p.depthMin);
                    maxD = std::max(maxD, p.depthMax);
                }
                totalBeams += p.beamCount;
            }
            os << std::fixed << std::setprecision(6);
            os << "Lat:    " << minLat << " to " << maxLat << "\n";
            os << "Lon:    " << minLon << " to " << maxLon << "\n";
            os << std::setprecision(2);
            if (minD < 1e17)
                os << "Depth:  " << minD << " to " << maxD << "\n";
            os << "Beams:  " << totalBeams << " total\n";
        } else if (fi.gsf.pingCount == 0) {
            os << "  (no bathymetry ping records — file may contain only metadata)\n";
        } else {
            os << "  (ping details omitted — count exceeds 10000)\n";
        }
    } else {
        auto& r = fi.raster;
        os << "Size:   " << r.width << " x " << r.height << " (" << r.bandCount << " band"
           << (r.bandCount != 1 ? "s" : "") << ")\n";
        os << std::fixed << std::setprecision(10);
        os << "Origin: (" << r.originX << ", " << r.originY << ")\n";
        os << "Pixel:  (" << r.pixelSizeX << ", " << r.pixelSizeY << ")\n";
        if (r.hasNoData)
            os << "NoData: " << r.noDataValue << "\n";
        if (!r.crsWkt.empty()) {
            OGRSpatialReference srs;
            srs.importFromWkt(r.crsWkt.c_str());
            const char* name = srs.GetName();
            const char* auth = srs.GetAuthorityName(nullptr);
            const char* code = srs.GetAuthorityCode(nullptr);
            os << "CRS:    ";
            if (name) os << name;
            if (auth && code) os << " [" << auth << ":" << code << "]";
            os << "\n";
        } else {
            os << "CRS:    (none)\n";
        }
    }
    return os.str();
}

// ---------------------------------------------------------------------------
// version()
// ---------------------------------------------------------------------------
std::string Version() {
    std::string v = "bathymetry/1.0 gdal/";
    v += GDALVersionInfo("RELEASE_NAME");
    v += " gsf/03.11";
    return v;
}

} // namespace bathy
