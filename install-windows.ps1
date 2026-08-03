# ============================================================
# Install Windows Exporter (Windows Server)
# Supports: Windows Server 2016, 2019, 2022 (on-prem / EC2 / VM)
#
# Usage (Admin PowerShell):
#   irm <RAW_URL>/install-windows.ps1 | iex
#   .\install-windows.ps1 [-Port 9182] [-Version 0.29.2]
# ============================================================

param(
    [string]$Version = "0.29.2",
    [int]$Port = 9182
)

$ErrorActionPreference = "Stop"
function Log  { Write-Host "[✓] $args" -ForegroundColor Green }
function Warn { Write-Host "[!] $args" -ForegroundColor Yellow }
function Err  { Write-Host "[✗] $args" -ForegroundColor Red; exit 1 }

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Err "Please run as Administrator"
}

$instanceId = $env:COMPUTERNAME
$instanceType = "unknown"
$region = "unknown"
$cloud = "unknown"
$privateIp = $null

try {
    Log "Trying EC2 metadata..."
    $token = Invoke-RestMethod -Method PUT -Uri "http://169.254.169.254/latest/api/token" `
        -Headers @{"X-aws-ec2-metadata-token-ttl-seconds" = "60"} -TimeoutSec 2
    $headers = @{"X-aws-ec2-metadata-token" = $token}

    $instanceId = Invoke-RestMethod "http://169.254.169.254/latest/meta-data/instance-id" -Headers $headers
    $instanceType = Invoke-RestMethod "http://169.254.169.254/latest/meta-data/instance-type" -Headers $headers
    $privateIp = Invoke-RestMethod "http://169.254.169.254/latest/meta-data/local-ipv4" -Headers $headers
    $az = Invoke-RestMethod "http://169.254.169.254/latest/meta-data/placement/availability-zone" -Headers $headers
    $region = $az -replace '.$', ''
    $cloud = "aws"
    Log "EC2 detected: $instanceId ($instanceType) | IP: $privateIp | AZ: $az"
}
catch {
    Warn "Not on EC2 (or metadata unavailable) — using local hostname/IP"
    $privateIp = (
        Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown" } |
        Select-Object -First 1 -ExpandProperty IPAddress
    )
    if (-not $privateIp) {
        $privateIp = (
            Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.IPAddress -notlike "127.*" } |
            Select-Object -First 1 -ExpandProperty IPAddress
        )
    }
}

if (-not $privateIp) {
    Err "Could not determine host IP address"
}

$url = "https://github.com/prometheus-community/windows_exporter/releases/download/v$Version/windows_exporter-$Version-amd64.msi"
$msi = Join-Path $env:TEMP "windows_exporter.msi"

Log "Downloading Windows Exporter v$Version..."
Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing

$collectors = "cpu,cs,logical_disk,memory,net,os,process,service,system,tcp"
Log "Installing..."
$msiArgs = "/i `"$msi`" /quiet ENABLED_COLLECTORS=$collectors LISTEN_PORT=$Port EXTRA_FLAGS=`"--collector.service.services-where=`"State='Running'`"`""
Start-Process msiexec.exe -ArgumentList $msiArgs -Wait

Log "Opening Windows Firewall port $Port..."
New-NetFirewallRule -DisplayName "Windows Exporter Prometheus $Port" `
    -Direction Inbound -Protocol TCP -LocalPort $Port `
    -Action Allow -ErrorAction SilentlyContinue | Out-Null

Start-Sleep -Seconds 3
$svc = Get-Service "windows_exporter" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Log "Service running OK"
}
else {
    Err "windows_exporter service is not running"
}

try {
    $r = Invoke-WebRequest "http://127.0.0.1:$Port/metrics" -UseBasicParsing -TimeoutSec 5
    if ($r.Content -match "windows_cpu") {
        Log "Metrics endpoint OK"
    }
    else {
        Err "Metrics endpoint returned unexpected content"
    }
}
catch {
    Err "Metrics endpoint did not respond on port $Port"
}

$hostname = $env:COMPUTERNAME
Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host " Add this scrape target to Prometheus" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host @"

  - job_name: '$hostname'
    scrape_interval: 15s
    static_configs:
      - targets: ['${privateIp}:${Port}']
        labels:
          hostname: '$hostname'
          instance_id: '$instanceId'
          instance_type: '$instanceType'
          region: '$region'
          cloud: '$cloud'
          os: 'windows'
"@
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Warn "Open firewall / security group inbound TCP $Port from Prometheus"
