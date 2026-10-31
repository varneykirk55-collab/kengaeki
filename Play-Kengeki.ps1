param([string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$model = Join-Path $projectRoot 'assets\models\kengeki\kengeki_character_animated.glb'
if (-not (Test-Path -LiteralPath $model)) {
    throw 'The private samurai GLB is missing. Run this in your existing Kengeki project, where the character already works.'
}

function Test-Godot43([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $version = (& $Path --headless --version 2>$null | Out-String).Trim()
        return $version -match '^4\.3(?:\.|\s|$)'
    } catch { return $false }
}

if ($GodotPath -and -not (Test-Godot43 $GodotPath)) {
    throw 'GodotPath must point to a Godot 4.3 executable.'
}
if (-not $GodotPath) {
    foreach ($name in @('godot', 'godot4', 'Godot_v4.3-stable_win64.exe', 'Godot_v4.3-stable_win64_console.exe')) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
        if ($command -and (Test-Godot43 $command.Source)) {
            $GodotPath = $command.Source
            break
        }
    }
}
if (-not $GodotPath) {
    $roots = @(
        (Split-Path $projectRoot -Parent),
        "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop",
        "$env:LOCALAPPDATA\Programs", 'C:\Tools', 'C:\Godot'
    )
    if ($env:OneDrive) { $roots += "$env:OneDrive\Desktop" }
    foreach ($directory in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        $candidates = Get-ChildItem -LiteralPath $directory -Filter '*godot*.exe' -File -Recurse -ErrorAction SilentlyContinue
        foreach ($candidate in $candidates) {
            if (Test-Godot43 $candidate.FullName) {
                $GodotPath = $candidate.FullName
                break
            }
        }
        if ($GodotPath) { break }
    }
}
if (-not $GodotPath) {
    Add-Type -AssemblyName System.Windows.Forms
    $picker = New-Object System.Windows.Forms.OpenFileDialog
    $picker.Title = 'Select your Godot 4.3 executable'
    $picker.Filter = 'Godot executable (*.exe)|*.exe'
    if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        $picker.Dispose()
        throw 'Launch cancelled.'
    }
    $GodotPath = $picker.FileName
    $picker.Dispose()
    if (-not (Test-Godot43 $GodotPath)) { throw 'Please select Godot 4.3.' }
}

Write-Host 'Importing project resources...'
& $GodotPath --headless --editor --path $projectRoot --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed; the game was not launched.' }
Write-Host 'Starting Kengeki with locomotion refinements.'
& $GodotPath --path $projectRoot
