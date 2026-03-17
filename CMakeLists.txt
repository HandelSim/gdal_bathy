cmake_minimum_required(VERSION 3.16)
project(bathymetry LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# GSF: always build from source (MSVC-aware; handles _fseeki64 etc.)
add_subdirectory("${CMAKE_SOURCE_DIR}/deps/gsf" "${CMAKE_BINARY_DIR}/deps/gsf" EXCLUDE_FROM_ALL)

if(MSVC)
    # Windows: vcpkg (or any system GDAL install) provides GDAL::GDAL imported target.
    # Configure with -DCMAKE_TOOLCHAIN_FILE=%VCPKG_ROOT%\scripts\buildsystems\vcpkg.cmake
    # or use the CMake preset: cmake --preset windows-vcpkg
    find_package(GDAL REQUIRED)
else()
    # Linux: use the bundled build in deps/gdal/ (override with -DGDAL_ROOT=<path>)
    if(NOT DEFINED GDAL_ROOT)
        set(GDAL_ROOT "${CMAKE_SOURCE_DIR}/deps/gdal")
    endif()
    find_library(GDAL_LIB NAMES gdal
        PATHS "${GDAL_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
endif()

add_library(bathymetry STATIC bathymetry.cpp)
target_include_directories(bathymetry
    PUBLIC  "${CMAKE_SOURCE_DIR}"
    PRIVATE "${CMAKE_SOURCE_DIR}/deps/gsf/src")
if(NOT MSVC)
    target_include_directories(bathymetry PRIVATE "${GDAL_ROOT}/include")
endif()

if(MSVC)
    target_link_libraries(bathymetry PRIVATE GDAL::GDAL gsf)
    target_compile_options(bathymetry PRIVATE /W4 /WX /std:c++17)
else()
    target_link_libraries(bathymetry PRIVATE ${GDAL_LIB} gsf)
    target_compile_options(bathymetry PRIVATE -Wall -Wextra -Wno-error)
    target_compile_definitions(bathymetry PRIVATE _LARGEFILE64_SOURCE _GNU_SOURCE)
endif()

add_executable(test_bathymetry test/test_bathymetry.cpp)
target_link_libraries(test_bathymetry PRIVATE bathymetry)

if(NOT MSVC)
    target_link_libraries(test_bathymetry PRIVATE dl m)
endif()
