param([string]$Serial, [switch]$Install)
$ErrorActionPreference = 'Stop'
$androidProject = Join-Path $PSScriptRoot 'android'
$sdk = $env:ANDROID_HOME
if (!$sdk) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
if (!(Test-Path -LiteralPath $sdk)) { throw 'Set ANDROID_HOME to your Android SDK directory.' }
$escapedSdk = $sdk.Replace('\', '/').Replace(':', '\:')
"sdk.dir=$escapedSdk" | Set-Content -LiteralPath (Join-Path $androidProject 'local.properties')
Push-Location $androidProject
try {
    & .\gradlew.bat :app:assembleDebug :app:testDebugUnitTest :app:lintDebug --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Android build/checks failed' }
    if ($Install) {
        if (!$Serial) { throw 'Specify -Serial explicitly to avoid installing on the wrong phone.' }
        $adb = Join-Path $sdk 'platform-tools\adb.exe'
        & $adb -s $Serial install -r 'app\build\outputs\apk\debug\app-debug.apk'
        if ($LASTEXITCODE -ne 0) { throw 'APK installation failed' }
        & $adb -s $Serial shell am start -W -n 'com.argus.garminpoc/.MainActivity'
        if ($LASTEXITCODE -ne 0) { throw 'APK launch failed' }
    }
} finally { Pop-Location }
