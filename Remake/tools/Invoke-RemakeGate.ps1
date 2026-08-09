[CmdletBinding()]
param(
    [ValidateSet('Quick', 'Content', 'Release')]
    [string]$Tier = 'Quick',
    [string]$GodotExecutable,
    [switch]$SkipWindowedChecks,
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
$gameRoot = Join-Path $remakeRoot 'game'
$mapEditorRoot = Join-Path $repositoryRoot 'MapEditor'
$resultRoot = Join-Path $remakeRoot 'LocalAssets\qa\gates'
$fixtureRoot = Join-Path $resultRoot 'fixtures'
$tierName = $Tier.ToLowerInvariant()
$summaryPath = Join-Path $resultRoot ("{0}-latest.json" -f $tierName)
$junitPath = Join-Path $resultRoot ("{0}-latest.junit.xml" -f $tierName)
New-Item -ItemType Directory -Force -Path $resultRoot, $fixtureRoot | Out-Null

$script:steps = [Collections.Generic.List[object]]::new()
$script:failedStep = ''
$script:started = Get-Date
$script:resumePassed = @{}

if ($Resume -and (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
    $previous = Get-Content -LiteralPath $summaryPath -Raw -Encoding utf8 | ConvertFrom-Json
    if ([string]$previous.tier -eq $tierName) {
        foreach ($step in @($previous.steps)) {
            if ([string]$step.status -eq 'passed') {
                $script:resumePassed[[string]$step.id] = $true
            }
        }
    }
}

function Resolve-GodotExecutable {
    param([string]$Requested)
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT4)) {
        return (Resolve-Path -LiteralPath $env:GODOT4).Path
    }
    $known = 'D:\Godot\Godot_v4.7.1-stable_win64_console.exe'
    if (Test-Path -LiteralPath $known -PathType Leaf) {
        return $known
    }
    $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        throw 'Godot 4 executable was not found.'
    }
    return $command.Source
}

$godot = Resolve-GodotExecutable $GodotExecutable

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Native command failed with exit code ${LASTEXITCODE}: $File $($Arguments -join ' ')"
    }
}

function Invoke-IsolatedGodotTest {
    param(
        [Parameter(Mandatory = $true)][string]$StepId,
        [Parameter(Mandatory = $true)][string]$Script,
        [string[]]$UserArguments = @(),
        [string]$CampaignRoot = ''
    )
    $safeId = $StepId -replace '[^a-zA-Z0-9._-]', '_'
    $saveRoot = Join-Path $resultRoot ("isolated\{0}\saves" -f $safeId)
    $defaultCampaignRoot = Join-Path $resultRoot ("isolated\{0}\campaigns" -f $safeId)
    New-Item -ItemType Directory -Force -Path $saveRoot, $defaultCampaignRoot | Out-Null
    $oldSaveRoot = $env:M1937_SAVE_ROOT
    $oldCampaignRoot = $env:M1937_USER_CAMPAIGN_ROOT
    try {
        $env:M1937_SAVE_ROOT = $saveRoot
        $env:M1937_USER_CAMPAIGN_ROOT = if ([string]::IsNullOrWhiteSpace($CampaignRoot)) {
            $defaultCampaignRoot
        }
        else {
            [IO.Path]::GetFullPath($CampaignRoot)
        }
        $arguments = @('--headless', '--path', $gameRoot, '--script', $Script)
        if ($UserArguments.Count -gt 0) {
            $arguments += '--'
            $arguments += $UserArguments
        }
        Invoke-NativeChecked -File $godot -Arguments $arguments
    }
    finally {
        $env:M1937_SAVE_ROOT = $oldSaveRoot
        $env:M1937_USER_CAMPAIGN_ROOT = $oldCampaignRoot
    }
}

function Invoke-GateStep {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$WorkPackage,
        [Parameter(Mandatory = $true)][string]$Reproduce,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string[]]$RequiredOutputs = @()
    )
    $canResume = $Resume -and $script:resumePassed.ContainsKey($Id)
    foreach ($required in $RequiredOutputs) {
        if (-not (Test-Path -LiteralPath $required)) {
            $canResume = $false
        }
    }
    if ($canResume) {
        $script:steps.Add([ordered]@{
            id = $Id; work_package = $WorkPackage; status = 'passed'; resumed = $true
            duration_seconds = 0.0; reproduce = $Reproduce; error = ''
        })
        Write-Host "[RESUME] $Id"
        return $true
    }
    Write-Host "[RUN] $Id"
    $started = Get-Date
    try {
        & $Action | Out-Host
        $script:steps.Add([ordered]@{
            id = $Id; work_package = $WorkPackage; status = 'passed'; resumed = $false
            duration_seconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
            reproduce = $Reproduce; error = ''
        })
        return $true
    }
    catch {
        $script:failedStep = $Id
        $script:steps.Add([ordered]@{
            id = $Id; work_package = $WorkPackage; status = 'failed'; resumed = $false
            duration_seconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
            reproduce = $Reproduce; error = [string]$_.Exception.Message
        })
        Write-Error "Gate step '$Id' failed: $($_.Exception.Message)" -ErrorAction Continue
        return $false
    }
}

function Write-GateReports {
    param([bool]$Passed)
    $finished = Get-Date
    $summary = [ordered]@{
        schema_version = 2
        tier = $tierName
        passed = $Passed
        failed_step = if ($Passed) { '' } else { $script:failedStep }
        started_at_utc = $script:started.ToUniversalTime().ToString('o')
        finished_at_utc = $finished.ToUniversalTime().ToString('o')
        duration_seconds = [Math]::Round(($finished - $script:started).TotalSeconds, 3)
        godot = $godot
        resume_enabled = [bool]$Resume
        global_pointer_control = $false
        isolated_user_directories = $true
        steps = @($script:steps)
    }
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    $document = [Xml.XmlDocument]::new()
    $suite = $document.CreateElement('testsuite')
    $suite.SetAttribute('name', "Remake-$tierName")
    $suite.SetAttribute('tests', [string]$script:steps.Count)
    $suite.SetAttribute('failures', [string](@($script:steps | Where-Object status -eq 'failed').Count))
    $suite.SetAttribute('time', [string]$summary.duration_seconds)
    $document.AppendChild($suite) | Out-Null
    foreach ($step in $script:steps) {
        $case = $document.CreateElement('testcase')
        $case.SetAttribute('classname', [string]$step.work_package)
        $case.SetAttribute('name', [string]$step.id)
        $case.SetAttribute('time', [string]$step.duration_seconds)
        if ([string]$step.status -eq 'failed') {
            $failure = $document.CreateElement('failure')
            $failure.SetAttribute('message', [string]$step.error)
            $failure.InnerText = "Reproduce: $($step.reproduce)"
            $case.AppendChild($failure) | Out-Null
        }
        elseif ([bool]$step.resumed) {
            $properties = $document.CreateElement('properties')
            $property = $document.CreateElement('property')
            $property.SetAttribute('name', 'resumed')
            $property.SetAttribute('value', 'true')
            $properties.AppendChild($property) | Out-Null
            $case.AppendChild($properties) | Out-Null
        }
        $suite.AppendChild($case) | Out-Null
    }
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [Text.UTF8Encoding]::new($false)
    $writer = [Xml.XmlWriter]::Create($junitPath, $settings)
    try { $document.Save($writer) } finally { $writer.Dispose() }
    Write-Host "Gate summary: $summaryPath"
    Write-Host "JUnit report: $junitPath"
}

function Stop-GateIfFailed {
    param([bool]$StepPassed)
    if ($StepPassed) { return }
    Write-GateReports -Passed $false
    throw "Remake $Tier gate failed at $script:failedStep."
}

Stop-GateIfFailed (Invoke-GateStep 'repository_guard' 'WP0' `
    'Remake/tools/Test-ModernizationRound2Guard.ps1' {
        & (Join-Path $PSScriptRoot 'Test-ModernizationRound2Guard.ps1')
    })
Stop-GateIfFailed (Invoke-GateStep 'localization_guard' 'WP6' `
    'Remake/tools/Check-RemakeLocalization.ps1' {
        & (Join-Path $PSScriptRoot 'Check-RemakeLocalization.ps1')
    })
Stop-GateIfFailed (Invoke-GateStep 'schema_documents' 'WP12' `
    'Get-ChildItem Remake/schemas/*.schema.json | ConvertFrom-Json' {
        $schemas = Get-ChildItem -LiteralPath (Join-Path $remakeRoot 'schemas') -Filter '*.schema.json'
        if ($schemas.Count -ne 5) { throw 'Exactly five public native-content schemas are required.' }
        foreach ($schema in $schemas) {
            $parsed = Get-Content -LiteralPath $schema.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$parsed.'$schema' -ne 'https://json-schema.org/draft/2020-12/schema') {
                throw "Unexpected JSON schema dialect: $($schema.Name)"
            }
        }
    })
Stop-GateIfFailed (Invoke-GateStep 'dotnet_remake_build' 'WP0,WP12' `
    'dotnet build Remake/1937Remake.slnx -c Release' {
        Invoke-NativeChecked dotnet @('build', (Join-Path $remakeRoot '1937Remake.slnx'), '-c', 'Release')
    })
Stop-GateIfFailed (Invoke-GateStep 'dotnet_resource_tests' 'WP0,WP12' `
    'dotnet run --project Remake/tools/ResourceFormats.Tests -c Release --no-build' {
        Invoke-NativeChecked dotnet @(
            'run', '--project', (Join-Path $remakeRoot 'tools\ResourceFormats.Tests\ResourceFormats.Tests.csproj'),
            '-c', 'Release', '--no-build')
    })
Stop-GateIfFailed (Invoke-GateStep 'dotnet_map_editor' 'WP12' `
    'dotnet run --project MapEditor/MapEditor.Tests -c Release' {
        $oldMapEditorTestRoot = $env:M1937_TEST_ROOT
        try {
            $env:M1937_TEST_ROOT = Join-Path $fixtureRoot 'mapeditor-tests'
            New-Item -ItemType Directory -Force -Path $env:M1937_TEST_ROOT | Out-Null
            Invoke-NativeChecked dotnet @(
                'run', '--project', (Join-Path $mapEditorRoot 'MapEditor.Tests\MapEditor.Tests.csproj'),
                '-c', 'Release')
        }
        finally {
            $env:M1937_TEST_ROOT = $oldMapEditorTestRoot
        }
    })
Stop-GateIfFailed (Invoke-GateStep 'godot_import_parse' 'WP1-WP12' `
    'Godot --headless --editor --path Remake/game --quit-after 3' {
        Invoke-NativeChecked $godot @('--headless', '--editor', '--path', $gameRoot, '--quit-after', '3')
    })

$quickTests = [ordered]@{
    'modernization_round2' = 'res://tests/modernization_round2_test.gd'
    'fixed_tick_persistence' = 'res://tests/fixed_tick_persistence_test.gd'
    'modernization_systems' = 'res://tests/modernization_systems_test.gd'
    'world_engine' = 'res://tests/world_engine_improvements_test.gd'
    'save_settings' = 'res://tests/save_settings_test.gd'
    'responsive_ui' = 'res://tests/responsive_ui_test.gd'
    'localization_contract' = 'res://tests/localization_contract_test.gd'
    'modern_ai_tactics' = 'res://tests/modern_ai_tactics_test.gd'
    'tactical_replay' = 'res://tests/tactical_replay_test.gd'
    'native_content_policy' = 'res://tests/native_content_policy_test.gd'
    'product_shell' = 'res://tests/product_shell_test.gd'
}
foreach ($entry in $quickTests.GetEnumerator()) {
    $id = "godot_$($entry.Key)"
    $scriptPath = [string]$entry.Value
    Stop-GateIfFailed (Invoke-GateStep $id 'WP1-WP11' `
        "Godot --headless --script $scriptPath" {
            Invoke-IsolatedGodotTest -StepId $id -Script $scriptPath
        })
}

if ($Tier -in @('Content', 'Release')) {
    $nativePackage = Join-Path $fixtureRoot 'synthetic.m1937pack'
    Stop-GateIfFailed (Invoke-GateStep 'native_pack_build' 'WP12' `
        'ResourceTool pack build Remake/examples/synthetic-pack-source synthetic.m1937pack' {
            Invoke-NativeChecked dotnet @(
                'run', '--project', (Join-Path $remakeRoot 'tools\ResourceTool\ResourceTool.csproj'),
                '-c', 'Release', '--no-build', '--', 'pack', 'build',
                (Join-Path $remakeRoot 'examples\synthetic-pack-source'), $nativePackage)
        } -RequiredOutputs @($nativePackage))
    Stop-GateIfFailed (Invoke-GateStep 'native_pack_runtime' 'WP12' `
        'Godot native_content_pack_test.gd --package=<synthetic>' {
            Invoke-IsolatedGodotTest -StepId 'native_pack_runtime' `
                -Script 'res://tests/native_content_pack_test.gd' `
                -UserArguments @("--package=$nativePackage")
        })
    Stop-GateIfFailed (Invoke-GateStep 'native_pack_product' 'WP12,replay' `
        'Godot native_content_product_test.gd --level=org.m1937.synthetic-training:training' {
            Invoke-IsolatedGodotTest -StepId 'native_pack_product' `
                -Script 'res://tests/native_content_product_test.gd' `
                -CampaignRoot $fixtureRoot `
                -UserArguments @(
                    '--level=org.m1937.synthetic-training:training',
                    '--content-id=org.m1937.synthetic-training:training',
                    '--skip-briefing', '--skip-level-selector')
        })
    $mapEditorPackage = Join-Path $fixtureRoot 'mapeditor-synthetic.m1937pack'
    Stop-GateIfFailed (Invoke-GateStep 'map_editor_pack_fixture' 'WP12' `
        'Copy latest isolated MapEditor synthetic export into the content fixture directory' {
            $candidate = Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'mapeditor-tests') `
                -Recurse -Filter 'mapeditor-synthetic.m1937pack' -File |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            if ($null -eq $candidate) { throw 'MapEditor did not produce its native package fixture.' }
            Copy-Item -LiteralPath $candidate.FullName -Destination $mapEditorPackage -Force
        } -RequiredOutputs @($mapEditorPackage))
    Stop-GateIfFailed (Invoke-GateStep 'map_editor_pack_product' 'WP12' `
        'Godot loads and completes the package emitted by MapEditor' {
            Invoke-IsolatedGodotTest -StepId 'map_editor_pack_product' `
                -Script 'res://tests/native_content_product_test.gd' `
                -CampaignRoot $fixtureRoot `
                -UserArguments @(
                    '--level=user.tests-synthetic:training',
                    '--content-id=user.tests-synthetic:training',
                    '--world-width=512', '--world-height=192',
                    '--expect-rich-content',
                    '--skip-briefing', '--skip-level-selector')
        })

    $realAssetManifest = Join-Path $remakeRoot 'LocalAssets\converted\levels\m000\level.json'
    if (Test-Path -LiteralPath $realAssetManifest -PathType Leaf) {
        $contentTests = [ordered]@{
            'real_input_journey' = 'res://tests/real_input_campaign_journey_test.gd'
            'real_door_runtime' = 'res://tests/real_door_runtime_test.gd'
            'real_mission_loop' = 'res://tests/real_mission_world_loop_test.gd'
            'real_inventory' = 'res://tests/real_original_inventory_test.gd'
            'real_corpse_reinforcement' = 'res://tests/real_corpse_reinforcement_test.gd'
        }
        foreach ($entry in $contentTests.GetEnumerator()) {
            $id = "godot_$($entry.Key)"
            $scriptPath = [string]$entry.Value
            Stop-GateIfFailed (Invoke-GateStep $id 'content-regression' `
                "Godot --headless --script $scriptPath -- --skip-briefing" {
                    Invoke-IsolatedGodotTest -StepId $id -Script $scriptPath `
                        -UserArguments @('--skip-briefing')
                })
        }
        if (-not $SkipWindowedChecks) {
            $productUiRoot = Join-Path $resultRoot 'content-product-ui'
            New-Item -ItemType Directory -Force -Path $productUiRoot | Out-Null
            foreach ($viewport in @('1024x768', '1920x1080')) {
                $viewportRoot = Join-Path $productUiRoot $viewport
                $viewportId = $viewport -replace 'x', '_'
                New-Item -ItemType Directory -Force -Path $viewportRoot | Out-Null
                Stop-GateIfFailed (Invoke-GateStep "product_ui_$viewportId" 'WP6,WP9' `
                    "Godot product_ui_probe.gd --resolution $viewport" {
                        Invoke-NativeChecked $godot @(
                            '--windowed', '--path', $gameRoot,
                            '--resolution', $viewport,
                            '--position', '100,100',
                            '--max-fps', '60',
                            '--disable-vsync',
                            '--log-file', (Join-Path $viewportRoot 'godot.log'),
                            '--script', 'res://tests/product_ui_probe.gd',
                            '--', "--output-dir=$viewportRoot")
                    })
            }
            Stop-GateIfFailed (Invoke-GateStep 'product_ui_screenshot_contract' 'WP6,WP9' `
                'Remake/tools/Test-ProductScreenshots.ps1' {
                    & (Join-Path $PSScriptRoot 'Test-ProductScreenshots.ps1') -ScreenshotRoot $productUiRoot
                })
        }
    }
    else {
        Write-Host '[SKIP] Real-asset content shards are unavailable; synthetic content coverage remains active.'
    }
}

if ($Tier -eq 'Release') {
    Stop-GateIfFailed (Invoke-GateStep 'legacy_verify_total' 'WP0-WP12' `
        'Remake/tools/Verify.ps1 -GodotExecutable <godot>' {
            & (Join-Path $PSScriptRoot 'Verify.ps1') -GodotExecutable $godot `
                -SkipWindowedChecks:$SkipWindowedChecks
        })
    Stop-GateIfFailed (Invoke-GateStep 'release_stability_30m' 'K' `
        'Remake/tools/Run-StabilitySoak.ps1 -DurationSeconds 1800 -Passes 3' {
            & (Join-Path $PSScriptRoot 'Run-StabilitySoak.ps1') `
                -GodotExecutable $godot -DurationSeconds 1800 -Passes 3 `
                -OutputDirectory (Join-Path $resultRoot 'release-stability')
        })
}

Write-GateReports -Passed $true
Write-Host "Remake $Tier gate passed ($($script:steps.Count) steps)."
