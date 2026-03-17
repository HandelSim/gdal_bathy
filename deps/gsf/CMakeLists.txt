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
    # F_OK (POSIX file-existence flag) is not defined in MSVC headers; it equals 0.
    # (_CRT_NONSTDC_NO_WARNINGS allows access() via <io.h> on MSVC.)
    F_OK=0)
  # htonl/ntohl/htons/ntohs live in Ws2_32 on Windows.
  # PUBLIC so any target that links gsf gets it automatically.
  target_link_libraries(gsf PUBLIC ws2_32)
else()
  # ftello64 / fseeko64 are GNU extensions
  target_compile_definitions(gsf PRIVATE _GNU_SOURCE _LARGEFILE64_SOURCE)
endif()

install(TARGETS gsf ARCHIVE DESTINATION lib)
install(DIRECTORY src/ DESTINATION include/gsf FILES_MATCHING PATTERN "*.h")
