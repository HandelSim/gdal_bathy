@echo off
set "PATH=C:\vcpkg\installed\x64-windows\bin;%PATH%"
set "GDAL_DATA=C:\Users\hande\AI\gdal_bathy\deps\gdal\share\gdal"
set "PROJ_DATA=C:\vcpkg\installed\x64-windows\share\proj"
set "PROJ_LIB=C:\vcpkg\installed\x64-windows\share\proj"
cd /d "C:\Users\hande\AI\gdal_bathy"
"build\Release\test_bathymetry.exe" 1>"test_stdout.txt" 2>"test_stderr.txt"
echo Exit:%ERRORLEVEL%>"test_exitcode.txt"
