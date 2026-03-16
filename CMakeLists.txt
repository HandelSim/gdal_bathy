cmake_minimum_required(VERSION 3.16)
project(bathymetry LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(GDAL_ROOT "${CMAKE_SOURCE_DIR}/deps/gdal")
set(GSF_ROOT  "${CMAKE_SOURCE_DIR}/deps/gsf")

find_library(GDAL_LIB NAMES gdal gdal_i
    PATHS "${GDAL_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)
find_library(GSF_LIB NAMES gsf
    PATHS "${GSF_ROOT}/lib" NO_DEFAULT_PATH REQUIRED)

add_library(bathymetry STATIC bathymetry.cpp)
target_include_directories(bathymetry
    PUBLIC  "${CMAKE_SOURCE_DIR}"
    PRIVATE "${GDAL_ROOT}/include"
            "${GSF_ROOT}/include/gsf")
target_link_libraries(bathymetry PRIVATE ${GDAL_LIB} ${GSF_LIB})

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
