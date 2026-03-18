# Called as a cmake -P script from the test_bathymetry POST_BUILD step.
# Required variables (passed via -D):
#   EXE         - full path to the built executable
#   OUT_DIR     - destination directory (same dir as the exe)
#   SEARCH_DIRS - pipe-separated (|) list of directories to search for DLLs

# Convert pipe-separated dirs back to a cmake list.
string(REPLACE "|" ";" _search_dirs "${SEARCH_DIRS}")

# Resolve every DLL the exe transitively depends on.
file(GET_RUNTIME_DEPENDENCIES
    EXECUTABLES        "${EXE}"
    RESOLVED_DEPENDENCIES_VAR   _resolved
    UNRESOLVED_DEPENDENCIES_VAR _unresolved
    DIRECTORIES        ${_search_dirs}
    # Skip Windows API sets and system DLLs.
    PRE_EXCLUDE_REGEXES  "api-ms-.*" "ext-ms-.*" "hvsifiletrust.*"
    POST_EXCLUDE_REGEXES ".*[/\\\\][Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\\\][Ss][Yy][Ss][Tt][Ee][Mm]32[/\\\\].*"
)

foreach(_dll ${_resolved})
    file(COPY "${_dll}" DESTINATION "${OUT_DIR}")
endforeach()

if(_unresolved)
    message(WARNING "Unresolved runtime dependencies (not copied):\n  ${_unresolved}")
endif()
