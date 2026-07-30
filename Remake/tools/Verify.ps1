[CmdletBinding()]
param(
    [string]$GodotExecutable
)

$ErrorActionPreference = 'Stop'
$remakeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$solution = Join-Path $remakeRoot '1937Remake.slnx'
$tests = Join-Path $PSScriptRoot 'ResourceFormats.Tests\ResourceFormats.Tests.csproj'
$resourceTool = Join-Path $PSScriptRoot 'ResourceTool\ResourceTool.csproj'
$game = Join-Path $remakeRoot 'game'
$realAssetManifest = Join-Path $remakeRoot 'LocalAssets\converted\levels\m000\level.json'
$localOcrScript = Join-Path `
    ([System.IO.Path]::GetDirectoryName($remakeRoot)) `
    'Patch\analysis\tools\Invoke-LocalScreenshotOcr.ps1'

& (Join-Path $PSScriptRoot 'Check-NoOriginalAssets.ps1')

dotnet build $solution --configuration Release
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed with exit code $LASTEXITCODE."
}

dotnet run --project $tests --configuration Release --no-build
if ($LASTEXITCODE -ne 0) {
    throw "Resource format tests failed with exit code $LASTEXITCODE."
}

& (Join-Path $PSScriptRoot 'Test-ModParityContract.ps1')
& (Join-Path $PSScriptRoot 'Test-CampaignPerformanceBaseline.ps1')
& (Join-Path $PSScriptRoot 'Test-OriginalInitialWeaponInventory.ps1')
& (Join-Path $PSScriptRoot 'Test-OriginalInitialItemInventory.ps1')
& (Join-Path $PSScriptRoot 'Test-OriginalWorldPickups.ps1')
& (Join-Path $PSScriptRoot 'Test-OriginalRuntimeActorCatalog.ps1')
if (Test-Path -LiteralPath $realAssetManifest -PathType Leaf) {
    & (Join-Path $PSScriptRoot 'Test-ModRuntimeIdentityCatalog.ps1') `
        -LevelManifest $realAssetManifest
}
else {
    & (Join-Path $PSScriptRoot 'Test-ModRuntimeIdentityCatalog.ps1')
}
& (Join-Path $PSScriptRoot 'Test-RuntimeParityTrace.ps1')

$modResource = Join-Path `
    ([System.IO.Path]::GetDirectoryName($remakeRoot)) `
    'Mod\1937Resources.GFL'
if ((Test-Path -LiteralPath $modResource -PathType Leaf) -and
    (Get-Item -LiteralPath $modResource).Length -gt 1000000) {
    dotnet run --project $resourceTool --configuration Release --no-build -- `
        inspect ([System.IO.Path]::GetDirectoryName($modResource))
    if ($LASTEXITCODE -ne 0) {
        throw "Stable Mod content-profile verification failed with exit code $LASTEXITCODE."
    }
}
else {
    Write-Host 'Stable Mod binary content is not materialized (for example, a Git LFS pointer); hash verification skipped.'
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

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_input_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot original input parity tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/combat_mission_runtime_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot combat and mission runtime tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/projectile_inventory_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot projectile and inventory tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/original_inventory_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot original inventory parity tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/backpack_inventory_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot backpack inventory parity tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/original_item_runtime_test.gd' -- --skip-briefing
if ($LASTEXITCODE -ne 0) {
    throw "Godot original item runtime tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_disguise_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot legacy disguise tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_world_items_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot legacy world-item tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_corpse_discovery_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot legacy corpse-discovery tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_enemy_ai_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot legacy enemy-AI tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_doors_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot legacy door tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/world_interactables_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot world interactable tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_special_actions_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot legacy special-action tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_explosion_visual_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot legacy explosion-visual tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/legacy_sb_commands_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot original S/B command tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/media_runtime_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot media catalog and fallback runtime tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/mission_direction_runtime_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot twelve-level mission direction tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/director_main_wiring_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot mission-director Main wiring tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/replay_validation_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot deterministic replay tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/runtime_parity_trace_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot runtime parity trace tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --quit-after 600 `
    --script 'res://tests/product_shell_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot product shell tests failed with exit code $LASTEXITCODE."
}

& $GodotExecutable --headless --path $game --script 'res://tests/save_settings_test.gd'
if ($LASTEXITCODE -ne 0) {
    throw "Godot save and settings tests failed with exit code $LASTEXITCODE."
}

if (Test-Path -LiteralPath $realAssetManifest -PathType Leaf) {
    & (Join-Path $PSScriptRoot 'Build-LevelFidelityBaselines.ps1') -Verify

    $parityProbeOutput = Join-Path $remakeRoot 'LocalAssets\qa\verify-parity'
    New-Item -ItemType Directory -Force -Path $parityProbeOutput | Out-Null
    & $GodotExecutable --headless --path $game `
        --max-fps 60 --disable-vsync `
        --script 'res://tests/parity_runtime_probe.gd' -- `
        "--output-dir=$parityProbeOutput"
    if ($LASTEXITCODE -ne 0) {
        throw "Godot real-content parity probe failed with exit code $LASTEXITCODE."
    }
    & $GodotExecutable --headless --path $game `
        --max-fps 60 --disable-vsync `
        --script 'res://tests/parity_runtime_probe.gd' -- `
        "--output-dir=$parityProbeOutput" `
        '--scenario-id=m000-obstacle-route-v1' `
        '--outbound-target=528,552' `
        '--return-target=304,136' `
        '--observation-seconds=0.75'
    if ($LASTEXITCODE -ne 0) {
        throw "Godot obstacle-route parity probe failed with exit code $LASTEXITCODE."
    }
    & $GodotExecutable --headless --path $game `
        --max-fps 60 --disable-vsync `
        --script 'res://tests/parity_runtime_probe.gd' -- `
        "--output-dir=$parityProbeOutput" `
        '--scenario-id=m000-enemy-patrol-v1' `
        '--observation-seconds=1.0'
    if ($LASTEXITCODE -ne 0) {
        throw "Godot enemy-patrol parity probe failed with exit code $LASTEXITCODE."
    }
    & $GodotExecutable --headless --path $game `
        --max-fps 60 --disable-vsync `
        --script 'res://tests/parity_runtime_probe.gd' -- `
        "--output-dir=$parityProbeOutput" `
        '--scenario-id=m000-natural-contact-v1' `
        '--outbound-target=1392,536' `
        '--return-target=1360,536' `
        '--observation-seconds=1.8'
    if ($LASTEXITCODE -ne 0) {
        throw "Godot natural-contact parity probe failed with exit code $LASTEXITCODE."
    }
    foreach ($parityScenarioId in @(
        'm000-basic-movement-v1',
        'm000-obstacle-route-v1'
    )) {
        $modParityBaseline = Join-Path $remakeRoot (
            'validation\baselines\mod\' +
            $parityScenarioId +
            '.json')
        & (Join-Path $PSScriptRoot 'Compare-RuntimeParityTrace.ps1') `
            -ReferenceTrace $modParityBaseline `
            -CandidateTrace (
                Join-Path $parityProbeOutput (
                    'remake-' + $parityScenarioId + '.json')) `
            -OutputJson (
                Join-Path $parityProbeOutput (
                    $parityScenarioId + '-comparison.json')) `
            -OutputMarkdown (
                Join-Path $parityProbeOutput (
                    $parityScenarioId + '-comparison.md')) | Out-Null
    }
    $patrolBaseline = Join-Path $remakeRoot (
        'validation\baselines\mod\m000-enemy-patrol-v1.json')
    $patrolCandidate = Join-Path $parityProbeOutput (
        'remake-m000-enemy-patrol-v1.json')
    & (Join-Path $PSScriptRoot 'Compare-RuntimeParityTrace.ps1') `
        -ReferenceTrace $patrolBaseline `
        -CandidateTrace $patrolCandidate `
        -ElapsedToleranceMs 500 `
        -AllowMismatch `
        -OutputJson (
            Join-Path $parityProbeOutput (
                'm000-enemy-patrol-v1-route-phase-comparison.json')) `
        -OutputMarkdown (
            Join-Path $parityProbeOutput (
                'm000-enemy-patrol-v1-route-phase-comparison.md')) | Out-Null
    & (Join-Path $PSScriptRoot 'Compare-PatrolKinematics.ps1') `
        -ReferenceTrace $patrolBaseline `
        -CandidateTrace $patrolCandidate `
        -OutputJson (
            Join-Path $parityProbeOutput (
            'm000-enemy-patrol-v1-kinematics.json')) | Out-Null

    $contactBaseline = Join-Path $remakeRoot (
        'validation\baselines\mod\m000-natural-contact-v1.json')
    $contactCandidate = Join-Path $parityProbeOutput (
        'remake-m000-natural-contact-v1.json')
    & (Join-Path $PSScriptRoot 'Compare-NaturalContactParity.ps1') `
        -ReferenceTrace $contactBaseline `
        -CandidateTrace $contactCandidate `
        -OutputJson (
            Join-Path $parityProbeOutput (
                'm000-natural-contact-v1-comparison.json')) | Out-Null

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
        --script 'res://tests/real_original_inventory_test.gd'
    if ($LASTEXITCODE -ne 0) {
        throw "Godot real 12-level original inventory tests failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $game `
        --script 'res://tests/real_corpse_reinforcement_test.gd' -- --skip-briefing
    if ($LASTEXITCODE -ne 0) {
        throw "Godot real corpse-reinforcement tests failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $game `
        --script 'res://tests/real_door_runtime_test.gd' -- --skip-briefing
    if ($LASTEXITCODE -ne 0) {
        throw "Godot real 12-level door runtime tests failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $game `
        --script 'res://tests/real_mission_world_loop_test.gd' -- --skip-briefing
    if ($LASTEXITCODE -ne 0) {
        throw "Godot real 12-level mission world-loop tests failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $game `
        --script 'res://tests/real_input_world_test.gd' -- --skip-briefing
    if ($LASTEXITCODE -ne 0) {
        throw "Godot real frame-input world test failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $game `
        --script 'res://tests/real_input_campaign_journey_test.gd' -- --skip-briefing
    if ($LASTEXITCODE -ne 0) {
        throw "Godot real 12-level product-input journey failed with exit code $LASTEXITCODE."
    }

    & $GodotExecutable --headless --path $game `
        --script 'res://tests/navigation_stress_test.gd' -- --level=m004
    if ($LASTEXITCODE -ne 0) {
        throw "Godot dense navigation stress test failed with exit code $LASTEXITCODE."
    }

    $campaignPerformanceOutput = Join-Path $remakeRoot (
        'LocalAssets\qa\verify-campaign-performance')
    & (Join-Path $PSScriptRoot 'Run-CampaignPerformance.ps1') `
        -GodotExecutable $GodotExecutable `
        -DurationSeconds 48 `
        -Passes 1 `
        -OutputDirectory $campaignPerformanceOutput `
        -ProfileId 'verify-twelve-level-windowed-short-v1'

    $productUiProbeOutput = Join-Path $remakeRoot 'LocalAssets\qa\verify-product-ui'
    New-Item -ItemType Directory -Force -Path $productUiProbeOutput | Out-Null
    & $GodotExecutable --windowed --path $game `
        --script 'res://tests/product_ui_probe.gd' -- `
        "--output-dir=$productUiProbeOutput"
    if ($LASTEXITCODE -ne 0) {
        throw "Godot product UI screenshot probe failed with exit code $LASTEXITCODE."
    }
    if (Test-Path -LiteralPath $localOcrScript -PathType Leaf) {
        Get-ChildItem -LiteralPath $productUiProbeOutput -Filter '*.jpg' -File |
            ForEach-Object {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass `
                    -File $localOcrScript -ImagePath $_.FullName
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Local OCR was unavailable for $($_.Name)."
                }
            }
    }
}

& $GodotExecutable --headless --path $game --quit-after 2
if ($LASTEXITCODE -ne 0) {
    throw "Godot scene smoke test failed with exit code $LASTEXITCODE."
}

Write-Host 'All remake checks passed.'
