# Builds signed release APKs into dist/:
#   NxSaves-<version>-arm64-v8a.apk    almost every phone from the last ~8 years (send this one)
#   NxSaves-<version>-armeabi-v7a.apk  older 32-bit phones
#   NxSaves-<version>-x86_64.apk       emulators / Chromebooks
#   NxSaves-<version>-universal.apk    works everywhere, but much larger
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\build_android.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
Set-Location $root

# JDK bug on Windows: Gradle fails with "Unable to establish loopback connection" when the temp
# folder path contains spaces or 8.3 short names. Point the JDK at a plain folder instead.
New-Item -ItemType Directory -Force 'C:\jdktmp' | Out-Null
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:/jdktmp'

if (-not (Test-Path 'android\key.properties')) {
    & (Join-Path $PSScriptRoot 'create_keystore.ps1')
}

$version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value

flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { throw 'Split APK build failed' }
$out = 'build\app\outputs\flutter-apk'
New-Item -ItemType Directory -Force 'dist' | Out-Null
foreach ($abi in 'arm64-v8a', 'armeabi-v7a', 'x86_64') {
    Copy-Item "$out\app-$abi-release.apk" "dist\NxSaves-$version-$abi.apk" -Force
}

flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'Universal APK build failed' }
Copy-Item "$out\app-release.apk" "dist\NxSaves-$version-universal.apk" -Force

Get-ChildItem dist\*.apk | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } | Format-Table -AutoSize
