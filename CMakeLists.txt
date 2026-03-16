cmake_minimum_required(VERSION 3.16)
project(bathymetry LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Allow caller to override with -DGDAL_ROOT=<path>.
# On Windows the bundled deps/gdal only has Linux .so files; point at a
# Windows-compatible install (OSGeo4W, vcpkg, or windows-deps/gdal/).
if(NOT DEFINED GDAL_ROOT)
  set(GDAL_ROOT "${CMAKE_SOURCE_DIR}/deps/gdal")
endif()

# GSF: build from source so it compiles correctly on every platform.
# The deps/gsf/CMakeLists.txt already handles MSVC (_fseeki64 etc.).
add_subdirectory("${CMAKE_SOURCE_DIR}/deps/gsf" "${CMAKE_BINARY_DIR}/deps/gsf" EXCLUDE_FROM_ALL)

find_library(GDAL_LIB NAMES gdal gdal_i
    PATHS "${GDAL_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)

add_library(bathymetry STATIC bathymetry.cpp)
target_include_directories(bathymetry
    PUBLIC  "${CMAKE_SOURCE_DIR}"
    PRIVATE "${GDAL_ROOT}/include"
            "${CMAKE_SOURCE_DIR}/deps/gsf/src")
target_link_libraries(bathymetry PRIVATE ${GDAL_LIB} gsf)

if(MSVC)
    target_compile_options(bathymetry PRIVATE /W4 /WX /std:c++17)
else()
    target_compile_options(bathymetry PRIVATE -Wall -Wextra -Wno-error)
    target_compile_definitions(bathymetry PRIVATE _LARGEFILE64_SOURCE _GNU_SOURCE)
endif()

add_executable(test_bathymetry test/test_bathymetry.cpp)
target_link_libraries(test_bathymetry PRIVATE bathymetry)

# On Linux, also need to link system libraries that GDAL depends on
if(NOT MSVC)
    target_link_libraries(test_bathymetry PRIVATE dl m)
endif()
