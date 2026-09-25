param([string]$SdkPath, [string]$KeyPath, [switch]$TestBuild)
$ErrorActionPreference = 'Stop'
if (!$SdkPath) { $SdkPath = (Get-Content (Join-Path $env:APPDATA 'Garmin\ConnectIQ\current-sdk.cfg') -Raw).Trim() }
if (!$KeyPath) { $KeyPath = Join-Path $PSScriptRoot '.local\developer_key.der' }
if (!(Test-Path -LiteralPath $KeyPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $KeyPath) | Out-Null
    $pocKey = [System.Security.Cryptography.RSA]::Create(4096)
    try { [IO.File]::WriteAllBytes($KeyPath, $pocKey.ExportPkcs8PrivateKey()) } finally { $pocKey.Dispose() }
}
$outputDir = Join-Path $PSScriptRoot 'garmin\bin'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$pocArgs = @('-f', (Join-Path $PSScriptRoot 'garmin\monkey.jungle'), '-d', 'fr55', '-y', $KeyPath, '-o', (Join-Path $outputDir 'LinkPoc.prg'), '-l', '0')
if ($TestBuild) { $pocArgs += '-t' }
& (Join-Path $SdkPath 'bin\monkeyc.bat') @pocArgs
if ($LASTEXITCODE -ne 0) { throw 'Forerunner 55 build failed' }
Write-Output "Built: $outputDir\LinkPoc.prg (fr55 only)"
