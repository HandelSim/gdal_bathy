cmake_minimum_required(VERSION 3.10)
project(gsf C)

file(GLOB GSF_SOURCES "src/*.c")
add_library(gsf STATIC ${GSF_SOURCES})
target_include_directories(gsf PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

if(MSVC)
  target_compile_definitions(gsf PRIVATE
    _CRT_SECURE_NO_WARNINGS
    _CRT_NONSTDC_NO_WARNINGS
    fseeko=_fseeki64
    ftello=_ftelli64
    # Windows 10 SDK (10.0.22000+) defines timespec in time.h.
    # HAVE_STRUCT_TIMESPEC is in gsf.h's guard list and skips its own definition.
    HAVE_STRUCT_TIMESPEC
    # F_OK (POSIX file-existence flag) is not defined in MSVC headers; it equals 0.
    F_OK=0)
else()
  # ftello64 / fseeko64 are GNU extensions
  target_compile_definitions(gsf PRIVATE _GNU_SOURCE _LARGEFILE64_SOURCE)
endif()

install(TARGETS gsf ARCHIVE DESTINATION lib)
install(DIRECTORY src/ DESTINATION include/gsf FILES_MATCHING PATTERN "*.h")
