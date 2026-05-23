# One-time fix for eloquentarduino/tflm_esp32 on ESP32:
# - Restores src/signal/micro (headers + kernels for micro_ops.h)
# - Keeps src/signal/src/*.h only (headers for src/*.cc)
# - Removes duplicate .cpp under src (causes "multiple definition" linker errors)
# - Moves src/_signal_disabled out of the compile tree
# - Removes broken precompiled=full from library.properties
$lib = Join-Path $env:USERPROFILE "Documents\Arduino\libraries\tflm_esp32"
if (-not (Test-Path $lib)) {
    Write-Error "tflm_esp32 not found at $lib — clone it first."
    exit 1
}

$props = Join-Path $lib "library.properties"
if (Test-Path $props) {
    (Get-Content $props) | Where-Object { $_ -notmatch '^precompiled=' } | Set-Content $props
    Write-Host "Removed precompiled=full from library.properties (if present)"
}

$signal = Join-Path $lib "src\signal"
$dupDisabled = Join-Path $lib "src\_signal_disabled"
$legacyExcluded = Join-Path $lib "signal_src_excluded"
$backup = Join-Path $lib "_signal_disabled_backup"

# Undo legacy patch that moved the whole signal tree out.
$legacy = Join-Path $lib "signal_excluded"
if (Test-Path $legacy) {
    if (Test-Path $signal) { Remove-Item $signal -Recurse -Force }
    Move-Item $legacy $signal
    Write-Host "Restored signal_excluded -> src/signal"
}

function Ensure-SignalLayout {
    param([string]$SourceRoot)
    if (-not (Test-Path $SourceRoot)) { return }

    $microSrc = Join-Path $SourceRoot "micro"
    $headersSrc = Join-Path $SourceRoot "src"
    $microDst = Join-Path $signal "micro"
    $headersDst = Join-Path $signal "src"

    if (Test-Path $microSrc) {
        if (Test-Path $microDst) { Remove-Item $microDst -Recurse -Force }
        New-Item -ItemType Directory -Force -Path (Split-Path $microDst -Parent) | Out-Null
        Copy-Item (Join-Path $microSrc "*") $microDst -Recurse -Force
        Write-Host "Copied micro kernels -> src/signal/micro"
    }

    if (Test-Path $headersSrc) {
        New-Item -ItemType Directory -Force -Path $headersDst | Out-Null
        Get-ChildItem $headersSrc -Recurse -Include *.h | ForEach-Object {
            $rel = $_.FullName.Substring($headersSrc.Length + 1)
            $out = Join-Path $headersDst $rel
            $outDir = Split-Path $out -Parent
            if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
            Copy-Item $_.FullName $out -Force
        }
        Write-Host "Copied headers -> src/signal/src (no .cpp)"
    }
}

# Primary fix: _signal_disabled under src/ is still compiled by Arduino IDE.
if (Test-Path $dupDisabled) {
    Ensure-SignalLayout -SourceRoot $dupDisabled
    if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
    Move-Item $dupDisabled $backup -Force
    Write-Host "Moved src/_signal_disabled -> _signal_disabled_backup (not compiled)"
}

$dupSrc = Join-Path $signal "src"
if (-not (Test-Path $signal)) {
    Write-Error "src/signal was not created — reinstall tflm_esp32 and re-run."
    exit 1
}
if (Test-Path $dupSrc) {
    Get-ChildItem $dupSrc -Recurse -Include *.cpp -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($dupSrc.Length + 1)
        $target = Join-Path $legacyExcluded $rel
        $targetDir = Split-Path $target -Parent
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
        Move-Item $_.FullName $target -Force
        Write-Host "Moved duplicate: signal/src/$rel"
    }
} elseif (Test-Path $legacyExcluded) {
    New-Item -ItemType Directory -Force -Path $dupSrc | Out-Null
    Get-ChildItem $legacyExcluded -Recurse -Include *.h | ForEach-Object {
        $rel = $_.FullName.Substring($legacyExcluded.Length + 1)
        $out = Join-Path $dupSrc $rel
        $outDir = Split-Path $out -Parent
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
        Copy-Item $_.FullName $out -Force
    }
    Write-Host "Restored headers to src/signal/src (kept .cpp in signal_src_excluded)"
}

if (-not (Test-Path (Join-Path $signal "micro\kernels\irfft.h"))) {
    Write-Error "Missing src/signal/micro/kernels/irfft.h — reinstall tflm_esp32, then re-run this script."
    exit 1
}
if (-not (Test-Path (Join-Path $dupSrc "circular_buffer.h"))) {
    Write-Error "Missing src/signal/src/circular_buffer.h — reinstall tflm_esp32, then re-run this script."
    exit 1
}
if (Test-Path $dupDisabled) {
    Write-Error "src/_signal_disabled still present — remove manually."
    exit 1
}

Write-Host "Done. In Arduino IDE: Sketch -> Clean Build Folder, then compile neuroguard_main."
