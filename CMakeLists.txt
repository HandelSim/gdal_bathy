cmake_minimum_required(VERSION 3.16)
project(bathymetry LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# GSF: always build from source (MSVC-aware; handles _fseeki64 etc.)
add_subdirectory("${CMAKE_SOURCE_DIR}/deps/gsf" "${CMAKE_BINARY_DIR}/deps/gsf" EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# Locate GDAL
#   vcpkg     : find_package(GDAL) works via the vcpkg toolchain; provides
#               the GDAL::GDAL imported target with correct include/lib/dll.
#   Windows   : bootstrap-windows.ps1 builds GDAL into windows-deps/gdal/
#               Override with -DGDAL_ROOT=<path>
#   Linux     : deps/gdal/ (pre-built in-repo)
#               Override with -DGDAL_ROOT=<path>
# ---------------------------------------------------------------------------
if(DEFINED CMAKE_TOOLCHAIN_FILE AND CMAKE_TOOLCHAIN_FILE MATCHES "vcpkg")
    find_package(GDAL CONFIG REQUIRED)
elseif(MSVC)
    if(NOT DEFINED GDAL_ROOT)
        set(GDAL_ROOT "${CMAKE_SOURCE_DIR}/windows-deps/gdal")
    endif()
    find_library(GDAL_LIB NAMES gdal
        PATHS "${GDAL_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
else()
    if(NOT DEFINED GDAL_ROOT)
        set(GDAL_ROOT "${CMAKE_SOURCE_DIR}/deps/gdal")
    endif()
    find_library(GDAL_LIB NAMES gdal
        PATHS "${GDAL_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
endif()

add_library(bathymetry STATIC bathymetry.cpp)
target_include_directories(bathymetry PUBLIC "${CMAKE_SOURCE_DIR}")

if(DEFINED CMAKE_TOOLCHAIN_FILE AND CMAKE_TOOLCHAIN_FILE MATCHES "vcpkg")
    # GDAL::GDAL imported target carries include dirs, lib, and dll info
    target_link_libraries(bathymetry PRIVATE GDAL::GDAL gsf)
else()
    target_include_directories(bathymetry
        PRIVATE "${CMAKE_SOURCE_DIR}/deps/gsf/src"
        PRIVATE "${GDAL_ROOT}/include")
    target_link_libraries(bathymetry PRIVATE "${GDAL_LIB}" gsf)
endif()

if(MSVC)
    target_compile_options(bathymetry PRIVATE /W4 /WX /std:c++17)
else()
    target_compile_options(bathymetry PRIVATE -Wall -Wextra -Wno-error)
    target_compile_definitions(bathymetry PRIVATE _LARGEFILE64_SOURCE _GNU_SOURCE)
endif()

add_executable(test_bathymetry test/test_bathymetry.cpp)
target_link_libraries(test_bathymetry PRIVATE bathymetry)

if(NOT MSVC)
    target_link_libraries(test_bathymetry PRIVATE dl m)
endif()

# ---------------------------------------------------------------------------
# Copy vcpkg DLLs next to the test exe so it runs without PATH changes
# ---------------------------------------------------------------------------
if(MSVC AND DEFINED CMAKE_TOOLCHAIN_FILE AND CMAKE_TOOLCHAIN_FILE MATCHES "vcpkg")
    add_custom_command(TARGET test_bathymetry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy -t
            "$<TARGET_FILE_DIR:test_bathymetry>"
            $<TARGET_RUNTIME_DLLS:test_bathymetry>
        COMMAND_EXPAND_LISTS
        COMMENT "Copying runtime DLLs to output directory"
    )
endif()
