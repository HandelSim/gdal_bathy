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
    ftello=_ftelli64)
endif()

install(TARGETS gsf ARCHIVE DESTINATION lib)
install(DIRECTORY src/ DESTINATION include/gsf FILES_MATCHING PATTERN "*.h")
