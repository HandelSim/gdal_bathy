#pragma once
#include <filesystem>
#include <string>
#include <vector>
#include <stdexcept>

namespace bathy {

enum class Format { BAG, GeoTIFF, XYZ, GSF, Unknown };

struct RasterInfo {
    int         width        = 0;
    int         height       = 0;
    int         bandCount    = 0;
    double      originX      = 0.0;   // top-left X (longitude or easting)
    double      originY      = 0.0;   // top-left Y (latitude or northing)
    double      pixelSizeX   = 0.0;   // positive eastward
    double      pixelSizeY   = 0.0;   // negative southward (standard convention)
    std::string crsWkt;               // empty string if coordinate system is unknown
    double      noDataValue  = 0.0;
    bool        hasNoData    = false;
};

struct GsfPingInfo {
    double latitude  = 0.0;
    double longitude = 0.0;
    double depthMin  = 0.0;
    double depthMax  = 0.0;
    int    beamCount = 0;
};

struct GsfInfo {
    int                      pingCount = 0;
    std::vector<GsfPingInfo> pings;    // populated only if pingCount <= 10000
};

struct FileInfo {
    Format     format = Format::Unknown;
    RasterInfo raster; // valid when format is BAG, GeoTIFF, or XYZ
    GsfInfo    gsf;    // valid when format is GSF
};

struct ConvertOptions {
    Format      targetFormat     = Format::GeoTIFF;

    // For BAG variable-resolution files: which layer to extract.
    // "LOW_RES" (default), "SUPERGRID:y:x", or "RESAMPLED:xres:yres"
    std::string bagMode          = "LOW_RES";

    // When source BAG has no embedded CRS, assume this EPSG code.
    int         assumedEpsg      = 4326;  // WGS84 geographic

    // GeoTIFF creation options
    std::string tiffCompression  = "DEFLATE";  // DEFLATE | LZW | NONE

    // XYZ column separator
    char        xyzSeparator     = ' ';

    // If true, throw std::runtime_error on any detectable data loss.
    bool        strictValidation = true;
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Detect format and read spatial/structural metadata.
/// Throws std::runtime_error on unreadable or corrupt input.
FileInfo QueryFile(const std::filesystem::path& inputPath);

/// Return a human-readable description of the file (similar to gdalinfo).
/// Includes format, dimensions, CRS, geo-transform, nodata, band info,
/// and for GSF files: ping count, lat/lon bounds, depth range.
std::string DescribeFile(const std::filesystem::path& inputPath);

/// Convert inputPath to outputPath in the format specified by opts.targetFormat.
/// Auto-detects the source format. Throws std::runtime_error on failure or
/// detected data loss when opts.strictValidation is true.
void ConvertFile(const std::filesystem::path& inputPath,
                 const std::filesystem::path& outputPath,
                 const ConvertOptions& opts = {});

/// Return a version string, e.g. "bathymetry/1.0 gdal/3.12.2"
std::string Version();

} // namespace bathy
