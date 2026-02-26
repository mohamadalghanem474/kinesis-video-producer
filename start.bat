@echo off
setlocal DisableDelayedExpansion

:: Setup ANSI colors
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "RESET=%ESC%[0m"
set "BOLD=%ESC%[1m"
set "RED=%ESC%[31m"
set "GREEN=%ESC%[32m"
set "YELLOW=%ESC%[33m"
set "BLUE=%ESC%[34m"
set "CYAN=%ESC%[36m"
set "MAGENTA=%ESC%[35m"

set "PREFIX=%BOLD%%BLUE%[%CYAN%AWS-KVS%BLUE%]%RESET%"
set "INFO=%PREFIX% %BOLD%%CYAN%[INFO]%RESET%"
set "SUCCESS=%PREFIX% %BOLD%%GREEN%[SUCCESS]%RESET%"
set "WARN=%PREFIX% %BOLD%%YELLOW%[WARN]%RESET%"
set "ERROR=%PREFIX% %BOLD%%RED%[ERROR]%RESET%"
set "STEP=%BOLD%%MAGENTA%>>>%RESET%"

cd /d "%~dp0"

echo.
echo %STEP% %BOLD%%WHITE%Checking Prerequisites (Windows)%RESET%
echo %YELLOW%---------------------------------------------------%RESET%

WHERE aws >nul 2>nul
IF %ERRORLEVEL% NEQ 0 (
    echo %WARN% %YELLOW%Installing AWS CLI...%RESET%
    winget install -e --id Amazon.AWSCLI --accept-source-agreements --accept-package-agreements
    echo %SUCCESS% %GREEN%AWS CLI installed. IMPORTANT: Please restart this script so it takes effect.%RESET%
    pause
    exit /b 0
) ELSE (
    echo %SUCCESS% %GREEN%AWS CLI is installed.%RESET%
)

WHERE docker >nul 2>nul
IF %ERRORLEVEL% NEQ 0 (
    echo %WARN% %YELLOW%Installing Docker Desktop...%RESET%
    winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
    echo %SUCCESS% %GREEN%Docker Desktop installed. Please start Docker Desktop manually, wait for it to initialize, and restart this script.%RESET%
    pause
    exit /b 0
) ELSE (
    echo %SUCCESS% %GREEN%Docker is installed.%RESET%
)

WHERE ffmpeg >nul 2>nul
IF %ERRORLEVEL% NEQ 0 (
    echo %WARN% %YELLOW%Installing FFmpeg...%RESET%
    winget install -e --id Gyan.FFmpeg --accept-source-agreements --accept-package-agreements
    echo %SUCCESS% %GREEN%FFmpeg installed. IMPORTANT: Please restart this script so it takes effect.%RESET%
    pause
    exit /b 0
) ELSE (
    echo %SUCCESS% %GREEN%FFmpeg is installed.%RESET%
)

echo.
echo %STEP% %BOLD%%WHITE%Waiting for Docker to be ready...%RESET%
echo %YELLOW%---------------------------------------------------%RESET%
docker info >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo %ERROR% %RED%Docker daemon is not running. Please start Docker Desktop and ensure it is fully loaded, then run again.%RESET%
    pause
    exit /b 1
)
echo %SUCCESS% %GREEN%Docker is ready.%RESET%

echo.
echo %STEP% %BOLD%%WHITE%AWS Configuration Check%RESET%
echo %YELLOW%---------------------------------------------------%RESET%
aws sts get-caller-identity >nul 2>&1
if errorlevel 1 (
    echo %WARN% %YELLOW%AWS CLI is not configured or session expired. Asking for configuration...%RESET%
    aws configure
) else (
    echo %SUCCESS% %GREEN%AWS is configured.%RESET%
)

echo.
echo %STEP% %BOLD%%WHITE%Authenticating Docker to AWS ECR%RESET%
echo %YELLOW%---------------------------------------------------%RESET%
aws ecr get-login-password --region us-west-2 | docker login -u AWS --password-stdin https://546150905175.dkr.ecr.us-west-2.amazonaws.com

echo.
echo %STEP% %BOLD%%WHITE%Cleaning up any old conflicting containers...%RESET%
echo %YELLOW%---------------------------------------------------%RESET%
docker rm -f mediamtx kinesis-producer >nul 2>&1

echo.
echo %STEP% %BOLD%%WHITE%Starting services using Docker Compose%RESET%
echo %YELLOW%---------------------------------------------------%RESET%
set KVS_IMAGE_SUFFIX=windows
docker compose up -d --quiet-pull

echo.
echo %STEP% %BOLD%%WHITE%Services Started! Waiting for mediamtx to warm up...%RESET%
echo %YELLOW%---------------------------------------------------%RESET%
timeout /t 5 /nobreak >nul

echo.
echo %STEP% %BOLD%%WHITE%Starting Camera Stream%RESET%
echo %YELLOW%---------------------------------------------------%RESET%
echo %INFO% %CYAN%Starting Windows Camera using FFmpeg...%RESET%
echo %INFO% %CYAN%Note: If this fails, you may need to find your actual camera name using: %BOLD%ffmpeg -list_devices true -f dshow -i dummy%RESET%
echo %INFO% %CYAN%and replace 'video="Integrated Camera"' in start.bat with your camera name.%RESET%
ffmpeg -f dshow -i video="Integrated Camera" -c:v libx264 -preset ultrafast -tune zerolatency -b:v 1500k -rtsp_transport tcp -f rtsp rtsp://localhost:8554/mystream

pause
