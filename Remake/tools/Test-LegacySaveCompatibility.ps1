[CmdletBinding()]
param(
    [string]$GodotExecutable,

    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$modDirectory = Join-Path $repositoryRoot 'Mod'
$toolProject = Join-Path $PSScriptRoot 'ResourceTool\ResourceTool.csproj'
$dataDirectory = Join-Path $remakeRoot 'game\data'
$gameDirectory = Join-Path $remakeRoot 'game'
$realAssetManifest = Join-Path (
    $remakeRoot) 'LocalAssets\converted\levels\m000\level.json'
$auditParent = [IO.Path]::GetFullPath(
    (Join-Path $remakeRoot 'LocalBuild\LegacySaveAudit'))
$auditDirectory = [IO.Path]::GetFullPath(
    (Join-Path $auditParent 'current'))

$requiredPaths = @(
    (Join-Path $modDirectory '1937Database.dbl')
)
$linkedPursuitCount = 0
$restoredSearchStepCount = 0
foreach ($index in 0..2) {
    $requiredPaths += Join-Path $modDirectory ('1937M{0:D3}.SAV' -f $index)
    $requiredPaths += Join-Path $modDirectory ('M1937.SI{0}' -f $index)
}
foreach ($index in 0..11) {
    $requiredPaths += Join-Path $modDirectory ('1937m{0:D3}.vwf' -f $index)
}
$missingOrPointer = @($requiredPaths | Where-Object {
    -not (Test-Path -LiteralPath $_ -PathType Leaf) -or
    (Get-Item -LiteralPath $_).Length -lt 10000
})
if ($missingOrPointer.Count -ne 0) {
    Write-Host (
        'Original SAV/SI binaries are not materialized; ' +
        'legacy differential verification skipped.')
    return
}

[IO.Directory]::CreateDirectory($auditParent) | Out-Null
if (Test-Path -LiteralPath $auditDirectory) {
    $resolvedExistingAudit = (Resolve-Path -LiteralPath $auditDirectory).Path
    $expectedPrefix = $auditParent.TrimEnd('\') + '\'
    if (-not $resolvedExistingAudit.StartsWith(
        $expectedPrefix,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace an audit directory outside $auditParent."
    }
    if ((Get-Item -LiteralPath $resolvedExistingAudit).Attributes -band
        [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing to replace reparse-point audit directory: $resolvedExistingAudit"
    }
    Remove-Item -LiteralPath $resolvedExistingAudit -Recurse -Force
}
[IO.Directory]::CreateDirectory($auditDirectory) | Out-Null

if (-not $NoBuild) {
    dotnet build $toolProject --configuration Release
    if ($LASTEXITCODE -ne 0) {
        throw "ResourceTool build failed with exit code $LASTEXITCODE."
    }
}

foreach ($index in 0..2) {
    $savePath = Join-Path $modDirectory ('1937M{0:D3}.SAV' -f $index)
    $previewPath = Join-Path $modDirectory ('M1937.SI{0}' -f $index)
    $slotId = 'legacy_{0:D3}' -f $index
    $outputPath = Join-Path $auditDirectory "$slotId.json"
    dotnet run --project $toolProject --configuration Release --no-build -- `
        import-save `
        $savePath `
        $modDirectory `
        $outputPath `
        $previewPath `
        "--slot=$slotId" `
        "--data-dir=$dataDirectory"
    if ($LASTEXITCODE -ne 0) {
        throw "Original save import failed for $slotId with exit code $LASTEXITCODE."
    }
}

foreach ($index in 0..2) {
    $slotId = 'legacy_{0:D3}' -f $index
    $outputPath = Join-Path $auditDirectory "$slotId.json"
    $document = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $actors = @($document.session.squad) +
        @($document.session.enemies) +
        @($document.session.escorts) +
        @($document.session.ambient)
    $actorScenes = @{}
    foreach ($actor in $actors) {
        $actorScenes[[int]$actor.scene_index] = $true
        if ($null -eq $actor.PSObject.Properties[
                'original_pursuit_actor_scene_index']) {
            throw "$slotId actor $($actor.scene_index) lost its pursuit scene field."
        }
    }
    foreach ($actor in $actors) {
        $targetScene = [int]$actor.original_pursuit_actor_scene_index
        if ($targetScene -ge 0 -and -not $actorScenes.ContainsKey($targetScene)) {
            throw (
                "$slotId actor $($actor.scene_index) pursuit target " +
                "$targetScene was not restored as an actor.")
        }
        if ($targetScene -ge 0) {
            ++$linkedPursuitCount
        }
    }
    foreach ($enemy in @($document.session.enemies)) {
        $searchStep = [int]$enemy.ai.legacy_enemy_ai.search_point_index
        if ($searchStep -lt 0 -or $searchStep -gt 5) {
            throw "$slotId enemy $($enemy.scene_index) has invalid search step $searchStep."
        }
        if ($searchStep -gt 0) {
            ++$restoredSearchStepCount
        }
    }
}
if ($linkedPursuitCount -eq 0 -or $restoredSearchStepCount -eq 0) {
    throw (
        'Legacy saves did not exercise pursuit links and search-step restoration: ' +
        "$linkedPursuitCount/$restoredSearchStepCount.")
}

if ([string]::IsNullOrWhiteSpace($GodotExecutable) -and
    -not [string]::IsNullOrWhiteSpace($env:GODOT4)) {
    $GodotExecutable = $env:GODOT4
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    foreach ($commandName in @('godot', 'godot4')) {
        $godotCommand = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -ne $godotCommand) {
            $GodotExecutable = $godotCommand.Source
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
    Write-Warning (
        'Godot was not found; strict SAV/SI conversion passed, ' +
        'but live Remake application was skipped.')
    return
}

$GodotExecutable = (Resolve-Path -LiteralPath $GodotExecutable).Path
if (-not $GodotExecutable.EndsWith(
    '_console.exe',
    [StringComparison]::OrdinalIgnoreCase)) {
    $consoleExecutable = Join-Path (
        [IO.Path]::GetDirectoryName($GodotExecutable)) (
        [IO.Path]::GetFileNameWithoutExtension($GodotExecutable) +
        '_console.exe')
    if (Test-Path -LiteralPath $consoleExecutable -PathType Leaf) {
        $GodotExecutable = $consoleExecutable
    }
}

$godotAuditPath = $auditDirectory.Replace('\', '/')
& $GodotExecutable --headless --path $gameDirectory `
    --script 'res://tests/legacy_save_import_test.gd' -- `
    "--save-directory=$godotAuditPath"
if ($LASTEXITCODE -ne 0) {
    throw "Converted legacy save schema test failed with exit code $LASTEXITCODE."
}

if (Test-Path -LiteralPath $realAssetManifest -PathType Leaf) {
    & $GodotExecutable --headless --path $gameDirectory `
        --script 'res://tests/real_legacy_save_apply_test.gd' -- `
        "--save-directory=$godotAuditPath"
    if ($LASTEXITCODE -ne 0) {
        throw "Live legacy save application test failed with exit code $LASTEXITCODE."
    }
}
else {
    Write-Host (
        'Converted LocalAssets are absent; schema verification passed, ' +
        'but live world application was skipped.')
}

Write-Host 'Original SAV/SI compatibility verification passed for three formal saves.'
