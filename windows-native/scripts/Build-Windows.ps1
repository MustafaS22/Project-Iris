[CmdletBinding()]
param(
    [ValidateSet('Debug','Release')][string]$Configuration = 'Release',
    [ValidateSet('x64','arm64')][string]$Architecture = 'x64',
    [switch]$Msix,
    [string]$CertificateThumbprint,
    [string]$TimestampUrl
)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Run this script in PowerShell 7 on Windows.' }
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $platform = if ($Architecture -eq 'arm64') { 'ARM64' } else { 'x64' }
    $rid = "win-$Architecture"
    $destination = Join-Path $root "artifacts/$Configuration/$Architecture"
    $publish = Join-Path $destination ("publish-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $publish -Force | Out-Null
    dotnet --info | Set-Content (Join-Path $destination 'dotnet-info.log')
    dotnet run --project tests/Iris.Core.Tests -c $Configuration 2>&1 | Tee-Object (Join-Path $destination 'tests.log')
    if ($LASTEXITCODE -ne 0) { throw 'Core checks failed.' }
    dotnet restore src/Iris.Windows/Iris.Windows.csproj --locked-mode -p:UseCurrentRuntimeIdentifier=false -p:SelfContained=true 2>&1 | Tee-Object (Join-Path $destination 'restore.log')
    if ($LASTEXITCODE -ne 0) { throw 'Locked Windows SDK restore failed.' }
    dotnet publish src/Iris.Windows/Iris.Windows.csproj --no-restore -c $Configuration -p:Platform=$platform -r $rid --self-contained true -o $publish 2>&1 | Tee-Object (Join-Path $destination 'publish.log')
    if ($LASTEXITCODE -ne 0) { throw 'WinUI publish failed.' }
    if (-not (Test-Path (Join-Path $publish 'Iris.exe'))) { throw 'Iris.exe is missing.' }
    $zip = Join-Path $destination "Iris-Windows-2.0-rc1-$Architecture-$Configuration.zip"
    Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $zip -Force
    Get-FileHash -Algorithm SHA256 $zip | Format-List | Out-File ($zip + '.sha256')

    if ($Msix) {
        $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
        $makeAppx = Get-ChildItem $kits -Filter makeappx.exe -Recurse | Where-Object { $_.Directory.Name -eq 'x64' } | Sort-Object FullName -Descending | Select-Object -First 1
        if (-not $makeAppx) { throw 'Windows SDK MakeAppx.exe is required for MSIX.' }
        $manifest = (Get-Content packaging/AppxManifest.xml -Raw).Replace('PROCESSOR_ARCHITECTURE', $Architecture)
        $manifest | Set-Content (Join-Path $publish 'AppxManifest.xml') -Encoding UTF8
        Copy-Item -Path packaging/Logos -Destination $publish -Recurse
        $package = Join-Path $destination "Iris-Windows-2.0-rc1-$Architecture-$Configuration.msix"
        & $makeAppx.FullName pack /d $publish /p $package /o
        if ($LASTEXITCODE -ne 0) { throw 'MSIX packaging failed.' }
        if ($CertificateThumbprint) {
            if ($TimestampUrl -notmatch '^https://') { throw 'Supply an approved HTTPS timestamp service.' }
            $signtool = Join-Path $makeAppx.Directory.FullName 'signtool.exe'
            & $signtool sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $package
            if ($LASTEXITCODE -ne 0) { throw 'MSIX signing failed.' }
            & $signtool verify /pa $package
            if ($LASTEXITCODE -ne 0) { throw 'MSIX signature verification failed.' }
        }
        Get-FileHash -Algorithm SHA256 $package | Format-List | Out-File ($package + '.sha256')
    }

    Get-ChildItem $destination -File | Select-Object Name,Length
}
finally { Pop-Location }
