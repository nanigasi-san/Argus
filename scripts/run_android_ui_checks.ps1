param(
    [string]$EmulatorId = "Medium_Phone_API_36.0",
    [switch]$CaptureScreenshots
)

$ErrorActionPreference = "Stop"

function Wait-ForAndroidDevice {
    param(
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $devices = & adb devices
        $online = $devices | Select-String "emulator-\d+\s+device"
        if ($online) {
            return ($online -split "\s+")[0]
        }
        Start-Sleep -Seconds 3
    }

    throw "Android emulator did not become ready within $TimeoutSeconds seconds."
}

$currentDevices = (& flutter devices) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list Flutter devices."
}
if ($currentDevices -notmatch "emulator-\d+") {
    Write-Host "Launching emulator: $EmulatorId"
    flutter emulators --launch $EmulatorId | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to launch Android emulator: $EmulatorId"
    }
}

$deviceId = Wait-ForAndroidDevice
Write-Host "Running integration_test on $deviceId"
New-Item -ItemType Directory -Force -Path "build/e2e" | Out-Null
$result = 0
$testRoots = @("integration_test", "e2e") | Where-Object { Test-Path -LiteralPath $_ }
$testFiles = @(Get-ChildItem -LiteralPath $testRoots -Recurse -File -Filter "*_test.dart" | Sort-Object FullName)
if ($testFiles.Count -eq 0) {
    throw "No E2E test files found in integration_test/ or e2e/."
}
$testFiles.FullName | Set-Content "build/e2e/suites.txt"
Set-Content "build/e2e/results.txt" -Value ""
foreach ($testFile in $testFiles) {
    $target = (Resolve-Path -LiteralPath $testFile.FullName -Relative).Replace('\', '/') -replace '^\./', ''
    $suite = $target -replace '_test\.dart$', '' -replace '/', '_'
    if ($CaptureScreenshots) {
        flutter drive --driver test_driver/ui_smoke_driver.dart --target $target -d $deviceId 2>&1 | Tee-Object -FilePath "build/e2e/${suite}.log"
    } else {
        flutter test $target -d $deviceId 2>&1 | Tee-Object -FilePath "build/e2e/${suite}.log"
    }
    if ($LASTEXITCODE -ne 0) {
        $result = 1
        Add-Content "build/e2e/results.txt" "${suite}: failure"
    } else {
        Add-Content "build/e2e/results.txt" "${suite}: success"
    }
}
& adb -s $deviceId logcat -d | Set-Content "build/e2e/logcat.txt"
if ($CaptureScreenshots) {
    Write-Host "Screenshots saved under build/integration_test/screenshots"
}
exit $result
