param([string]$Serial, [ValidateRange(1,65535)][int]$Port = 8787)
$ErrorActionPreference = 'Stop'
$labAdb = Get-Command adb.exe -ErrorAction SilentlyContinue
$labAdbPath = if ($labAdb) { $labAdb.Source } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe' }
if (-not (Test-Path -LiteralPath $labAdbPath)) {
    Write-Host 'ADB is unavailable. Use Chrome USB port forwarding instead:'
    Write-Host "chrome://inspect/#devices -> Port forwarding -> $Port -> localhost:$Port"
    Write-Host "Then open http://localhost:$Port/?mode=phone in phone Chrome."
    exit 1
}
$labDevices = & $labAdbPath devices
if ($LASTEXITCODE -ne 0) { throw 'ADB could not list connected devices.' }
$labOnline = @($labDevices | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if (-not $Serial) {
    if ($labOnline.Count -ne 1) { throw 'Connect one authorized Android phone, or pass -Serial explicitly.' }
    $Serial = $labOnline[0]
}
if ($Serial -notin $labOnline) { throw 'The chosen phone is not connected and authorized for USB debugging.' }
& $labAdbPath -s $Serial reverse "tcp:$Port" "tcp:$Port"
if ($LASTEXITCODE -ne 0) { throw 'USB reverse forwarding failed.' }
& $labAdbPath -s $Serial shell am start -a android.intent.action.VIEW -d "http://localhost:$Port/?mode=phone"
Write-Host "Phone: http://localhost:$Port/?mode=phone"
Write-Host "PC receiver: http://localhost:$Port/?mode=receiver"
