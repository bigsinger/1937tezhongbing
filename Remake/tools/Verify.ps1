[CmdletBinding()]
param(
    [string]$GodotExecutable
)

$ErrorActionPreference = 'Stop'
$remakeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$solution = Join-Path $remakeRoot '1937Remake.slnx'
$tests = Join-Path $PSScriptRoot 'ResourceFormats.Tests\ResourceFormats.Tests.csproj'
$game = Join-Path $remakeRoot 'game'
$realAssetManifest = Join-Path $remakeRoot 'LocalAssets\converted\levels\m000\level.json'

& (Join-Path $PSScriptRoot 'Check-NoOriginalAssets.ps1')

dotnet build $solution --configuration Release
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed with exit code $LASTEXITCODE."
}

dotnet run --project $tests --configuration Release --no-build
if ($LASTEXITCODE -ne 0) {
    throw "Resource format tests failed with exit code $LASTEXITCODE."
}

if ([string]::IsNullOrWhiteSpace($GodotExecutable) -and -not [string]::IsNullOrWhiteSpace($env:GODOT4)) {
    $GodotExecutable = $env:GODOT4
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -eq $godotCommand) {
        $godotCommand = Get-Command godot4 -ErrorAction SilentlyContinue
    }
    if ($null -ne $godotCommand) {
        $GodotExecutable = $godotCommand.Source
    }
}

if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    Write-Warning 'Godot was not found; .NET and asset guard checks passed, but Godot tests were skipped.'
    exit 0
}

$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
if (-not $GodotExecutable.EndsWith('_console.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
    $consoleExecutable = Join-Path `
        ([System.IO.Path]::GetDirectoryName($GodotExecutable)) `
        (([System.IO.Path]::GetFileNameWithoutExtension($GodotExecutable)) + '_console.exe')
    if (Test-Path -LiteralPath $consoleExecutable -PathType Leaf) {
        $GodotExecutable = $consoleExecutable
    }
}

# A fresh checkout has no `.godot/global_script_class_cache.cfg`. Prime the
# project once before compiling scripts individually so `class_name` types are
# available regardless of filesystem enumeration order. Existing developer
# checkouts usually hide this dependency because the editor created the cache.
& $GodotExecutable --headless --editor --path $game --quit-after 2
if ($LASTEXITCODE -ne 0) {
    throw "Godot project initialization failed with exit code $LASTEXITCODE."
}

Get-ChildItem -LiteralPath $game -Recurse -Filter '*.gd' | ForEach-Object {
    $relativePath = ($_.FullName.Substring($game.Length) -replace '^[\\/]+', '') -replace '\\', '/'
    $resourcePath = "res://$relativePath"
    & $GodotExecutable --headless --path $game --script $resourcePath --check-only
    if ($LASTEXITCODE -ne 0) {
        throw "Godot parse check failed for $resourcePath with exit code $LASTEXITCODE."
    }
}

& $GodotExecutable --headless --path $game --script 'res://tests/test_runner.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot logic tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/combat_mission_runtime_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot combat and mission runtime tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/projectile_inventory_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot projectile and inventory tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/world_interactables_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot world interactable tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/media_runtime_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot media catalog and fallback runtime tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/replay_validation_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot deterministic replay tests failed with exit code $LASTEXITCODE."
}

if (Test-Path -LiteralPath $realAssetManifest -PathType Leaf) {
    $realMediaCatalog = Join-Path $remakeRoot 'LocalAssets\converted\legacy-media-catalog.json'
    if (Test-Path -LiteralPath $realMediaCatalog -PathType Leaf) {
        & $GodotExecutable --headless --path $game --script 'res://tests/real_media_test.gd'
        if ($LASTEXITCODE -ne 0) {
            throw "Godot real imported-media tests failed with exit code $LASTEXITCODE."
        }
    }

    & $GodotExecutable --headless --path $game --script 'res://tests/real_assets_test.gd'
    if ($LASTEXITCODE -ne 0) {
        throw "Godot real imported-asset tests failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $game `
        --script 'res://tests/navigation_stress_test.gd' -- --level=m004
    if ($LASTEXITCODE -ne 0) {
        throw "Godot dense navigation stress test failed with exit code $LASTEXITCODE."
    }
}

& $GodotExecutable --headless --path $game --quit-after 2
if ($LASTEXITCODE -ne 0) {
    throw "Godot scene smoke test failed with exit code $LASTEXITCODE."
}

Write-Host 'All remake checks passed.'
