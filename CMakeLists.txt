cmake_minimum_required(VERSION 3.16)
project(bathymetry LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# GSF: always build from source (MSVC-aware; handles _fseeki64 etc.)
add_subdirectory("${CMAKE_SOURCE_DIR}/deps/gsf" "${CMAKE_BINARY_DIR}/deps/gsf" EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# Locate GDAL
#   Windows + vcpkg : vcpkg toolchain injects its installed/x64-windows into
#                     find_library search paths automatically.
#   Windows + local : bootstrap-windows.ps1 builds GDAL into windows-deps/gdal/
#                     Override with -DGDAL_ROOT=<path>
#   Linux           : deps/gdal/ (pre-built in-repo)
#                     Override with -DGDAL_ROOT=<path>
# ---------------------------------------------------------------------------
if(MSVC)
    if(NOT DEFINED GDAL_ROOT)
        set(GDAL_ROOT "${CMAKE_SOURCE_DIR}/windows-deps/gdal")
    endif()
    # vcpkg toolchain adds its installed/x64-windows to the search even with
    # NO_DEFAULT_PATH, so this finds gdal.lib from vcpkg when GDAL_ROOT is empty.
    find_library(GDAL_LIB NAMES gdal gdal_i
        PATHS "${GDAL_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
else()
    if(NOT DEFINED GDAL_ROOT)
        set(GDAL_ROOT "${CMAKE_SOURCE_DIR}/deps/gdal")
    endif()
    find_library(GDAL_LIB NAMES gdal
        PATHS "${GDAL_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
endif()

message(STATUS "GDAL library: ${GDAL_LIB}")

add_library(bathymetry STATIC bathymetry.cpp)
target_include_directories(bathymetry
    PUBLIC  "${CMAKE_SOURCE_DIR}"
    PRIVATE "${CMAKE_SOURCE_DIR}/deps/gsf/src")

if(MSVC)
    # Derive include dir: <gdal_root>/include alongside <gdal_root>/lib
    get_filename_component(_gdal_lib_dir "${GDAL_LIB}" DIRECTORY)
    get_filename_component(_gdal_root_dir "${_gdal_lib_dir}" DIRECTORY)
    target_include_directories(bathymetry PRIVATE "${_gdal_root_dir}/include")
    target_link_libraries(bathymetry PRIVATE "${GDAL_LIB}" gsf)
    target_compile_options(bathymetry PRIVATE /W4 /WX /std:c++17)
else()
    target_include_directories(bathymetry PRIVATE "${GDAL_ROOT}/include")
    target_link_libraries(bathymetry PRIVATE ${GDAL_LIB} gsf)
    target_compile_options(bathymetry PRIVATE -Wall -Wextra -Wno-error)
    target_compile_definitions(bathymetry PRIVATE _LARGEFILE64_SOURCE _GNU_SOURCE)
endif()

add_executable(test_bathymetry test/test_bathymetry.cpp)
target_link_libraries(test_bathymetry PRIVATE bathymetry)

if(NOT MSVC)
    target_link_libraries(test_bathymetry PRIVATE dl m)
endif()

# ---------------------------------------------------------------------------
# Copy GDAL (and sibling) DLLs next to test_bathymetry.exe on Windows so it
# runs from the repo root without PATH changes.
# The bin/ dir sits alongside the lib/ dir where gdal.lib was found.
# ---------------------------------------------------------------------------
if(MSVC AND GDAL_LIB)
    get_filename_component(_gdal_lib_dir "${GDAL_LIB}" DIRECTORY)
    get_filename_component(_gdal_root_dir "${_gdal_lib_dir}" DIRECTORY)
    set(_gdal_bin_dir "${_gdal_root_dir}/bin")
    add_custom_command(TARGET test_bathymetry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${_gdal_bin_dir}"
            "$<TARGET_FILE_DIR:test_bathymetry>"
        COMMENT "Copying GDAL runtime DLLs from ${_gdal_bin_dir}"
    )
endif()
