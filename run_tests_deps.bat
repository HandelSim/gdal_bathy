@echo off
set "PATH=C:\Users\hande\AI\gdal_bathy\deps\gdal\bin;%PATH%"
set "GDAL_DATA=C:\Users\hande\AI\gdal_bathy\deps\gdal\share\gdal"
set "PROJ_DATA=C:\Users\hande\AI\gdal_bathy\deps\gdal\share\proj"
set "PROJ_LIB=C:\Users\hande\AI\gdal_bathy\deps\gdal\share\proj"
cd /d "C:\Users\hande\AI\gdal_bathy"
"build-deps-gdal\Release\test_bathymetry.exe" 1>"test_stdout.txt" 2>"test_stderr.txt"
echo Exit:%ERRORLEVEL%>"test_exitcode.txt"
