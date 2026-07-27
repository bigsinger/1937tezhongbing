[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^m\d{3}$')]
    [string]$MissionId,

    [string]$RepositoryRoot = '',
    [string]$WorkDirectory = '',
    [switch]$SkipPreview
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot '..\..'))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
$RepositoryRoot = $RepositoryRoot.TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar)

if ([string]::IsNullOrWhiteSpace($WorkDirectory)) {
    $temporaryRoot = if (Test-Path -LiteralPath 'E:\1937') {
        'E:\1937'
    }
    else {
        [IO.Path]::GetTempPath()
    }
    $WorkDirectory = Join-Path $temporaryRoot (
        "1937-vwf\$MissionId")
}
$WorkDirectory = [IO.Path]::GetFullPath($WorkDirectory)
[IO.Directory]::CreateDirectory($WorkDirectory) | Out-Null

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Description must be a non-empty repository-relative path."
    }
    $fullPath = [IO.Path]::GetFullPath(
        (Join-Path $RepositoryRoot $RelativePath))
    $rootPrefix = $RepositoryRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith(
            $rootPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes the repository root: $RelativePath"
    }
    return $fullPath
}

function Get-RequiredText {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or
        [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        throw "mission-package.json is missing required property '$Name'."
    }
    return [string]$property.Value
}

function Invoke-DotnetTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project,
        [Parameter(Mandatory = $true)]
        [string[]]$ToolArguments
    )

    $arguments = @(
        'run', '--project', $Project, '-c', 'Release', '--'
    ) + $ToolArguments
    & dotnet @arguments
    if ($LASTEXITCODE -ne 0) {
        throw (
            "Tool '$([IO.Path]::GetFileNameWithoutExtension($Project))' " +
            "failed with exit code $LASTEXITCODE.")
    }
}

function Publish-FileAtomically {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    $destinationDirectory = [IO.Path]::GetDirectoryName($Destination)
    [IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
    $pending = $Destination + ".pending.$PID"
    $backup = $Destination + ".previous.$PID"
    try {
        Copy-Item -LiteralPath $Source -Destination $pending -Force
        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            [IO.File]::Replace(
                $pending, $Destination, $backup, $true)
        } else {
            [IO.File]::Move($pending, $Destination)
        }
    } finally {
        if (Test-Path -LiteralPath $pending -PathType Leaf) {
            Remove-Item -LiteralPath $pending -Force
        }
        if (Test-Path -LiteralPath $backup -PathType Leaf) {
            Remove-Item -LiteralPath $backup -Force
        }
    }
}

$missionDirectory = Resolve-RepositoryPath `
    -RelativePath "MapEditor/Missions/$MissionId" `
    -Description 'mission directory'
$packagePath = Join-Path $missionDirectory 'mission-package.json'
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Mission package manifest not found: $packagePath"
}

$package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ([int]$package.schema_version -ne 1) {
    throw 'Only mission-package.json schema_version 1 is supported.'
}
if ((Get-RequiredText $package 'id') -cne $MissionId) {
    throw "Manifest id does not match requested mission '$MissionId'."
}
$null = Get-RequiredText $package 'title'

$mode = (Get-RequiredText $package 'mode').ToLowerInvariant()
if ($mode -notin @('redeploy', 'composite')) {
    throw "Unsupported mission package mode '$mode'."
}
$selectorLevel = [int]$package.selector_level
$engineMission = [int]$package.engine_mission
if ($selectorLevel -lt 1 -or $engineMission -lt 1 -or
    $engineMission -gt 12) {
    throw 'selector_level must be positive and engine_mission must be 1..12.'
}
$expectedSelectorLevel = [int]$MissionId.Substring(1) + 1
if ($selectorLevel -ne $expectedSelectorLevel) {
    throw (
        "selector_level $selectorLevel does not match $MissionId " +
        "(expected $expectedSelectorLevel).")
}

$source = Resolve-RepositoryPath `
    -RelativePath (Get-RequiredText $package 'source_vwf') `
    -Description 'source_vwf'
$output = Resolve-RepositoryPath `
    -RelativePath (Get-RequiredText $package 'output_vwf') `
    -Description 'output_vwf'
$missionDefinition = Resolve-RepositoryPath `
    -RelativePath (Get-RequiredText $package 'mission_definition') `
    -Description 'mission_definition'
$missionReport = Resolve-RepositoryPath `
    -RelativePath (Get-RequiredText $package 'mission_report') `
    -Description 'mission_report'
$expectedOutputHash = (
    Get-RequiredText $package 'expected_output_sha256').ToUpperInvariant()
$runtimeVwf = Get-RequiredText $package 'runtime_vwf'
if ($source.Equals(
        $output,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'source_vwf and output_vwf must be different files.'
}

foreach ($requiredFile in @($source, $missionDefinition)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required mission input does not exist: $requiredFile"
    }
}
if ($expectedOutputHash -notmatch '^[0-9A-F]{64}$') {
    throw 'expected_output_sha256 must contain 64 hexadecimal characters.'
}
$expectedOutputName = "1937$MissionId.vwf"
if (-not [IO.Path]::GetFileName($output).Equals(
        $expectedOutputName,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw (
        "output_vwf must end in '$expectedOutputName' for $MissionId.")
}
if ($runtimeVwf -cne ([IO.Path]::GetFileName($output).ToUpperInvariant())) {
    throw (
        "runtime_vwf '$runtimeVwf' does not match output file " +
        "'$([IO.Path]::GetFileName($output).ToUpperInvariant())'.")
}

$builder = Resolve-RepositoryPath `
    -RelativePath 'MapEditor/tools/VwfMissionBuilder/VwfMissionBuilder.csproj' `
    -Description 'mission builder'
$missionSource = $source
$compositionReport = $null
$candidateCompositionReport = $null

if ($mode -eq 'composite') {
    $blueprint = Resolve-RepositoryPath `
        -RelativePath (Get-RequiredText $package 'blueprint_definition') `
        -Description 'blueprint_definition'
    $compositionReport = Resolve-RepositoryPath `
        -RelativePath (Get-RequiredText $package 'composition_report') `
        -Description 'composition_report'
    $candidateCompositionReport = Join-Path $WorkDirectory 'composition.md'
    $composedName = Get-RequiredText $package 'composed_work_file'
    if ([IO.Path]::IsPathRooted($composedName) -or
        [IO.Path]::GetFileName($composedName) -cne $composedName) {
        throw 'composed_work_file must be a single file name.'
    }
    $missionSource = Join-Path $WorkDirectory $composedName
    $composer = Resolve-RepositoryPath `
        -RelativePath (
            'MapEditor/tools/VwfBlueprintComposer/' +
            'VwfBlueprintComposer.csproj') `
        -Description 'blueprint composer'
    Invoke-DotnetTool -Project $composer -ToolArguments @(
        $source, $missionSource, $blueprint, $candidateCompositionReport)
}

$candidateOutput = Join-Path $WorkDirectory (
    [IO.Path]::GetFileName($output))
$candidateMissionReport = Join-Path $WorkDirectory 'validation.md'
Invoke-DotnetTool -Project $builder -ToolArguments @(
    $missionSource, $candidateOutput,
    $missionDefinition, $candidateMissionReport)

$actualOutputHash = (
    Get-FileHash -LiteralPath $candidateOutput -Algorithm SHA256
).Hash.ToUpperInvariant()
if ($actualOutputHash -cne $expectedOutputHash) {
    throw (
        "Deterministic output hash mismatch for $MissionId. Expected " +
        "$expectedOutputHash, actual $actualOutputHash. Review the source, " +
        "definition and candidates in '$WorkDirectory' before accepting a " +
        'new baseline. The published VWF and reports were not changed.')
}

Publish-FileAtomically -Source $candidateOutput -Destination $output
Publish-FileAtomically `
    -Source $candidateMissionReport `
    -Destination $missionReport
if ($mode -eq 'composite') {
    Publish-FileAtomically `
        -Source $candidateCompositionReport `
        -Destination $compositionReport
}

if ($mode -eq 'composite' -and -not $SkipPreview -and
    $env:OS -eq 'Windows_NT') {
    $previewSource = Resolve-RepositoryPath `
        -RelativePath (Get-RequiredText $package 'preview_source_terrain') `
        -Description 'preview_source_terrain'
    $previewOutput = Resolve-RepositoryPath `
        -RelativePath (Get-RequiredText $package 'preview_output_directory') `
        -Description 'preview_output_directory'
    $previewScript = Resolve-RepositoryPath `
        -RelativePath (
            'MapEditor/tools/VwfBlueprintComposer/' +
            'Compose-PreviewAssets.ps1') `
        -Description 'preview composer'
    & $previewScript `
        -SourceTerrain $previewSource `
        -Blueprint $blueprint `
        -OutputDirectory $previewOutput
}

[pscustomobject]@{
    Id = $MissionId
    Mode = $mode
    SelectorLevel = $selectorLevel
    EngineMission = $engineMission
    RuntimeVwf = $runtimeVwf
    Output = $output
    Sha256 = $actualOutputHash
    MissionReport = $missionReport
    CompositionReport = $compositionReport
    WorkDirectory = $WorkDirectory
}
