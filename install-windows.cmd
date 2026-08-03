@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Install Windows Exporter (CMD / no PowerShell required)
REM Supports: Windows Server 2016, 2019, 2022 (on-prem / EC2 / VM)
REM
REM Usage (Admin Command Prompt):
REM   install-windows.cmd
REM   install-windows.cmd 9182
REM
REM One-liner after repo is public:
REM   curl -fsSL -o %TEMP%\install-windows.cmd <RAW_URL>/install-windows.cmd && %TEMP%\install-windows.cmd
REM ============================================================

set "VERSION=0.29.2"
set "PORT=9182"
if not "%~1"=="" set "PORT=%~1"

set "COLLECTORS=cpu,cs,logical_disk,memory,net,os,process,service,system,tcp"
set "MSI=%TEMP%\windows_exporter.msi"
set "URL=https://github.com/prometheus-community/windows_exporter/releases/download/v%VERSION%/windows_exporter-%VERSION%-amd64.msi"

net session >nul 2>&1
if errorlevel 1 (
  echo [X] Please run as Administrator
  exit /b 1
)

echo [+] Installing Windows Exporter v%VERSION% on port %PORT%

set "INSTANCE_ID=%COMPUTERNAME%"
set "INSTANCE_TYPE=unknown"
set "REGION=unknown"
set "CLOUD=unknown"
set "PRIVATE_IP="

REM Try EC2 IMDSv2 (ignore errors on non-EC2)
curl.exe -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --connect-timeout 2 --max-time 3 > "%TEMP%\ec2_token.txt" 2>nul
set /p EC2_TOKEN=<"%TEMP%\ec2_token.txt"
if defined EC2_TOKEN (
  for /f "usebackq delims=" %%I in (`curl.exe -s -H "X-aws-ec2-metadata-token: !EC2_TOKEN!" "http://169.254.169.254/latest/meta-data/instance-id" --connect-timeout 2 --max-time 3 2^>nul`) do set "INSTANCE_ID=%%I"
  for /f "usebackq delims=" %%I in (`curl.exe -s -H "X-aws-ec2-metadata-token: !EC2_TOKEN!" "http://169.254.169.254/latest/meta-data/instance-type" --connect-timeout 2 --max-time 3 2^>nul`) do set "INSTANCE_TYPE=%%I"
  for /f "usebackq delims=" %%I in (`curl.exe -s -H "X-aws-ec2-metadata-token: !EC2_TOKEN!" "http://169.254.169.254/latest/meta-data/local-ipv4" --connect-timeout 2 --max-time 3 2^>nul`) do set "PRIVATE_IP=%%I"
  for /f "usebackq delims=" %%I in (`curl.exe -s -H "X-aws-ec2-metadata-token: !EC2_TOKEN!" "http://169.254.169.254/latest/meta-data/placement/availability-zone" --connect-timeout 2 --max-time 3 2^>nul`) do set "AZ=%%I"
  if defined PRIVATE_IP (
    set "CLOUD=aws"
    if defined AZ set "REGION=!AZ:~0,-1!"
    echo [+] EC2 detected: !INSTANCE_ID! ^(!INSTANCE_TYPE!^) ^| IP: !PRIVATE_IP!
  )
)

REM Fallback: first non-loopback IPv4 from ipconfig
if not defined PRIVATE_IP (
  echo [!] Not on EC2 or metadata unavailable — using local IP
  for /f "tokens=2 delims=:" %%A in ('ipconfig ^| findstr /c:"IPv4 Address"') do (
    for /f "tokens=* delims= " %%B in ("%%A") do (
      echo %%B | findstr /b "127." >nul
      if errorlevel 1 if not defined PRIVATE_IP set "PRIVATE_IP=%%B"
    )
  )
)

if not defined PRIVATE_IP (
  echo [X] Could not determine host IP address
  exit /b 1
)

echo [+] Downloading Windows Exporter...
where curl.exe >nul 2>&1
if errorlevel 1 (
  echo [!] curl.exe not found — trying certutil
  certutil -urlcache -split -f "%URL%" "%MSI%" >nul
) else (
  curl.exe -fsSL "%URL%" -o "%MSI%"
)
if errorlevel 1 (
  echo [X] Download failed
  exit /b 1
)
if not exist "%MSI%" (
  echo [X] MSI not found after download
  exit /b 1
)

echo [+] Installing MSI...
msiexec.exe /i "%MSI%" /quiet ENABLED_COLLECTORS=%COLLECTORS% LISTEN_PORT=%PORT% EXTRA_FLAGS="--collector.service.services-where=""State='Running'"""
if errorlevel 1 (
  echo [X] MSI install failed
  exit /b 1
)

echo [+] Opening Windows Firewall port %PORT%...
netsh advfirewall firewall delete rule name="Windows Exporter Prometheus %PORT%" >nul 2>&1
netsh advfirewall firewall add rule name="Windows Exporter Prometheus %PORT%" dir=in action=allow protocol=TCP localport=%PORT% >nul

timeout /t 3 /nobreak >nul

sc query windows_exporter | findstr /I "RUNNING" >nul
if errorlevel 1 (
  echo [X] windows_exporter service is not running
  exit /b 1
)
echo [+] Service running OK

curl.exe -fsS "http://127.0.0.1:%PORT%/metrics" 2>nul | findstr /C:"windows_cpu" >nul
if errorlevel 1 (
  echo [X] Metrics endpoint did not respond on port %PORT%
  exit /b 1
)
echo [+] Metrics endpoint OK

echo.
echo ======================================================
echo  Add this scrape target to Prometheus
echo ======================================================
echo.
echo   - job_name: '%COMPUTERNAME%'
echo     scrape_interval: 15s
echo     static_configs:
echo       - targets: ['%PRIVATE_IP%:%PORT%']
echo         labels:
echo           hostname: '%COMPUTERNAME%'
echo           instance_id: '%INSTANCE_ID%'
echo           instance_type: '%INSTANCE_TYPE%'
echo           region: '%REGION%'
echo           cloud: '%CLOUD%'
echo           os: 'windows'
echo.
echo ======================================================
echo.
echo [!] Open firewall / security group inbound TCP %PORT% from Prometheus
exit /b 0
