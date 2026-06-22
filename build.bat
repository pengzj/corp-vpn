@echo off
setlocal
set ROOT=%~dp0
set RELEASES=%ROOT%releases

echo =^> Building frontend...
cd /d "%ROOT%frontend"
call yarn install --silent
call yarn build

if not exist "%RELEASES%\macOS"   mkdir "%RELEASES%\macOS"
if not exist "%RELEASES%\Linux"   mkdir "%RELEASES%\Linux"
if not exist "%RELEASES%\Windows" mkdir "%RELEASES%\Windows"

cd /d "%ROOT%backend"

echo =^> macOS Apple Silicon (M1/M2/M3)...
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
copy "zig-out\bin\ops_vpn" "%RELEASES%\macOS\ops_vpn-M1"

echo =^> macOS Intel...
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe
copy "zig-out\bin\ops_vpn" "%RELEASES%\macOS\ops_vpn-Intel"

echo =^> Linux 64-bit...
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe
copy "zig-out\bin\ops_vpn" "%RELEASES%\Linux\ops_vpn"

echo =^> Windows 64-bit...
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe
copy "zig-out\bin\ops_vpn.exe" "%RELEASES%\Windows\ops_vpn.exe"

echo.
echo Done! releases\:
echo.
echo   macOS\
dir "%RELEASES%\macOS"
echo   Linux\
dir "%RELEASES%\Linux"
echo   Windows\
dir "%RELEASES%\Windows"
