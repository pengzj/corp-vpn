@echo off
setlocal
set ROOT=%~dp0
set RELEASES=%ROOT%releases

echo =^> Building frontend...
cd /d "%ROOT%frontend"
call yarn install --silent
call yarn build

REM Clear zig cache to force re-embedding of updated www/ files
echo =^> Clearing zig cache...
if exist "%ROOT%backend\.zig-cache" rmdir /s /q "%ROOT%backend\.zig-cache"

REM Clean and recreate release directories
echo =^> Cleaning releases\...
if exist "%RELEASES%" rmdir /s /q "%RELEASES%"
mkdir "%RELEASES%\macOS"
mkdir "%RELEASES%\Linux"
mkdir "%RELEASES%\Windows"

cd /d "%ROOT%backend"

echo =^> macOS Apple Silicon (M1/M2/M3)...
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
copy "zig-out\bin\ops_vpn" "%RELEASES%\macOS\ops_vpn-M1"
cd /d "%RELEASES%\macOS"
powershell Compress-Archive -Force -Path "ops_vpn-M1" -DestinationPath "ops_vpn-macOS-M1.zip"
del "ops_vpn-M1"
cd /d "%ROOT%backend"

echo =^> macOS Intel...
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe
copy "zig-out\bin\ops_vpn" "%RELEASES%\macOS\ops_vpn-Intel"
cd /d "%RELEASES%\macOS"
powershell Compress-Archive -Force -Path "ops_vpn-Intel" -DestinationPath "ops_vpn-macOS-Intel.zip"
del "ops_vpn-Intel"
cd /d "%ROOT%backend"

echo =^> Linux 64-bit...
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe
copy "zig-out\bin\ops_vpn" "%RELEASES%\Linux\ops_vpn"
cd /d "%RELEASES%\Linux"
powershell Compress-Archive -Force -Path "ops_vpn" -DestinationPath "ops_vpn-Linux.zip"
del "ops_vpn"
cd /d "%ROOT%backend"

echo =^> Windows 64-bit...
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe
copy "zig-out\bin\ops_vpn.exe" "%RELEASES%\Windows\ops_vpn.exe"
cd /d "%RELEASES%\Windows"
powershell Compress-Archive -Force -Path "ops_vpn.exe" -DestinationPath "ops_vpn-Windows.zip"
del "ops_vpn.exe"
cd /d "%ROOT%backend"

echo.
echo Done! releases\:
echo.
echo   macOS\
dir "%RELEASES%\macOS"
echo   Linux\
dir "%RELEASES%\Linux"
echo   Windows\
dir "%RELEASES%\Windows"
echo.
echo Upload zips to GitLab Releases: https://git.ringcentral.com/rc-ai-learning/francis-peng-vpn/-/releases/new
