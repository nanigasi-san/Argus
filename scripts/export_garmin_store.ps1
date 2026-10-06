param(
    [string]$DeveloperKey = (Join-Path $env:USERPROFILE '.garmin/argus/developer_key.der'),
    [string]$Version = '0.1.1',
    [string]$OutputDirectory = 'build/garmin-store/multi-device'
)

$ErrorActionPreference = 'Stop'
$argusRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$argusSdkConfig = Join-Path $env:APPDATA 'Garmin/ConnectIQ/current-sdk.cfg'
$argusSdk = (Get-Content -LiteralPath $argusSdkConfig -Raw).Trim()
$argusCompiler = Join-Path $argusSdk 'bin/monkeyc.bat'
if (!(Test-Path -LiteralPath $argusCompiler)) { throw 'Connect IQ compiler is unavailable.' }
if (!(Test-Path -LiteralPath $DeveloperKey)) { throw 'The existing developer signing key is unavailable.' }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must use major.minor.patch format.' }

$argusOutputDirectory = [IO.Path]::GetFullPath((Join-Path $argusRoot $OutputDirectory))
[void][IO.Directory]::CreateDirectory($argusOutputDirectory)
[xml]$argusManifest = Get-Content -LiteralPath (Join-Path $argusRoot 'garmin/argus-data-field/manifest.xml') -Raw
$argusNs = [Xml.XmlNamespaceManager]::new($argusManifest.NameTable)
$argusNs.AddNamespace('iq', 'http://www.garmin.com/xml/connectiq')
$argusApplication = $argusManifest.SelectSingleNode('//iq:application', $argusNs)
$argusApplication.SetAttribute('version', $Version)
# Export every explicitly supported product; do not restrict the Store package to fr55.
$argusProducts = @($argusManifest.SelectNodes('//iq:products/iq:product', $argusNs) | ForEach-Object { $_.GetAttribute('id') })
if ($argusProducts.Count -eq 0) { throw 'The manifest contains no products.' }
foreach ($argusProduct in $argusProducts) {
    $argusDeviceDefinition = Join-Path $env:APPDATA "Garmin/ConnectIQ/Devices/$argusProduct/compiler.json"
    if (!(Test-Path -LiteralPath $argusDeviceDefinition)) {
        throw "Install the Connect IQ SDK device definition for $argusProduct before exporting."
    }
}

$argusManifestPath = Join-Path $argusOutputDirectory 'manifest-store.xml'
$argusXmlSettings = [Xml.XmlWriterSettings]::new()
$argusXmlSettings.Indent = $true
$argusXmlSettings.Encoding = [Text.UTF8Encoding]::new($false)
$argusWriter = [Xml.XmlWriter]::Create($argusManifestPath, $argusXmlSettings)
try { $argusManifest.Save($argusWriter) } finally { $argusWriter.Dispose() }

$argusProject = (Join-Path $argusRoot 'garmin/argus-data-field').Replace('\', '/')
$argusJungle = Join-Path $argusOutputDirectory 'monkey-store.jungle'
$argusJungleText = @"
project.manifest = manifest-store.xml
base.sourcePath = $argusProject/source;$argusProject/tests
base.resourcePath = $argusProject/resources
"@
[IO.File]::WriteAllText($argusJungle, $argusJungleText, [Text.UTF8Encoding]::new($false))
$argusOutput = Join-Path $argusOutputDirectory "ARGUS-$Version.iq"
$argusLog = Join-Path $argusOutputDirectory 'export.log'
& $argusCompiler -e -r -f $argusJungle -y $DeveloperKey -o $argusOutput -l 0 *> $argusLog
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath $argusLog -Tail 40
    throw "Connect IQ package export failed: $LASTEXITCODE"
}
$argusReceipt = [ordered]@{
    version = $Version
    appId = $argusApplication.GetAttribute('id')
    minApiLevel = $argusApplication.GetAttribute('minApiLevel')
    products = $argusProducts
    sdk = (Get-Content -LiteralPath (Join-Path $argusSdk 'bin/version.txt') -Raw).Trim()
    file = $argusOutput
    bytes = (Get-Item -LiteralPath $argusOutput).Length
    sha256 = (Get-FileHash -LiteralPath $argusOutput -Algorithm SHA256).Hash
}
$argusReceipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $argusOutputDirectory 'package-receipt.json') -Encoding utf8
$argusReceipt | ConvertTo-Json -Depth 4
