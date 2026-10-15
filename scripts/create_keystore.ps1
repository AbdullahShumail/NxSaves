# Creates the release signing key for the Android APK (android/keystore/nxsaves-release.jks) and
# android/key.properties. Run once. BACK BOTH FILES UP: installed copies of NxSaves can only be
# updated by an APK signed with the same key.
$ErrorActionPreference = 'Stop'
$android = Join-Path (Split-Path $PSScriptRoot) 'android'
$keystoreDir = Join-Path $android 'keystore'
$keystore = Join-Path $keystoreDir 'nxsaves-release.jks'
$properties = Join-Path $android 'key.properties'

if (Test-Path $keystore) {
    Write-Host "A keystore already exists at $keystore - not overwriting it."
    exit 0
}

$keytool = 'keytool'
if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\keytool.exe'))) {
    $keytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
}

$bytes = New-Object byte[] 24
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$password = [Convert]::ToBase64String($bytes) -replace '[+/=]', ''

New-Item -ItemType Directory -Force $keystoreDir | Out-Null
& $keytool -genkeypair -keystore $keystore -storetype PKCS12 -alias nxsaves `
    -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=NxSaves, O=Private' `
    -storepass $password -keypass $password
if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }

@"
storeFile=keystore/nxsaves-release.jks
storePassword=$password
keyAlias=nxsaves
keyPassword=$password
"@ | Set-Content -Encoding ascii $properties

Write-Host "Created $keystore and $properties. Back them up somewhere safe."
