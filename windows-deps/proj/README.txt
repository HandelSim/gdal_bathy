PROJ Windows x64 MSVC binaries were not available at build time.

Best options to obtain them:

Option 1 — OSGeo4W installer (easiest):
  Download https://download.osgeo.org/osgeo4w/v2/osgeo4w-setup.exe
  Install packages: proj, proj-devel
  Copy from C:\OSGeo4W\:
    include\proj.h         -> windows-deps\proj\include\
    lib\proj.lib           -> windows-deps\proj\lib\
    bin\proj_9*.dll        -> windows-deps\proj\bin\
    share\proj\            -> windows-deps\proj\share\proj\

Option 2 — vcpkg:
  vcpkg install proj:x64-windows
  Copy from vcpkg\installed\x64-windows\

Option 3 — Build from source:
  https://proj.org/en/stable/install.html
