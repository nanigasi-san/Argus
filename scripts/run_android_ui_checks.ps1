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
if ($currentDevices -notmatch "android") {
    Write-Host "Launching emulator: $EmulatorId"
    flutter emulators --launch $EmulatorId | Out-Null
}

$deviceId = Wait-ForAndroidDevice
Write-Host "Running integration_test on $deviceId"
if ($CaptureScreenshots) {
    $screenshotDir = "build\\integration_test\\screenshots"
    if (Test-Path $screenshotDir) {
        Remove-Item -LiteralPath $screenshotDir -Recurse -Force
    }
    flutter drive --driver test_driver/ui_smoke_driver.dart --target integration_test/ui_smoke_test.dart -d $deviceId
    Write-Host "Screenshots saved under $screenshotDir"
} else {
    flutter test integration_test/ui_smoke_test.dart -d $deviceId
}
