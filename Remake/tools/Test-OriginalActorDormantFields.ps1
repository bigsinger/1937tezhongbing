[CmdletBinding()]
param(
    [string]$CatalogPath = '',
    [string]$GameDirectory = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$remakeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $remakeRoot '..'))
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path `
        $remakeRoot `
        'game\data\original_actor_dormant_fields.json'
}
if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
    $GameDirectory = Join-Path $repositoryRoot 'Mod'
}

function Read-Utf8Json {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Required actor-field catalog is missing: $LiteralPath"
    }
    return [IO.File]::ReadAllText(
        [IO.Path]::GetFullPath($LiteralPath),
        [Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
}

function Get-CanonicalTextSha256 {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    $text = [IO.File]::ReadAllText(
        [IO.Path]::GetFullPath($LiteralPath),
        [Text.UTF8Encoding]::new($false))
    $canonical = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($canonical)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $algorithm.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
    }
}

$catalog = Read-Utf8Json -LiteralPath $CatalogPath
if ([int]$catalog.schema_version -ne 1 -or
    [string]$catalog.catalog_id -ne
        'original-actor-dormant-fields-v1' -or
    [string]$catalog.content_profile -ne
        'repository-mod-12-level-20260729' -or
    [string]$catalog.source.database_file -ne '1937Database.dbl' -or
    [string]$catalog.source.database_sha256 -ne
        '0017D8AB6A41F104BF0DE9A8282AB593B94E2BF7131038566AC281A8F15025D9' -or
    [string]$catalog.source.executable_file -ne 'M1937.exe' -or
    [string]$catalog.source.executable_sha256 -ne
        'F4DD1131DF6C993C01EA011F9439BC725E6DC6491B5FBBA47724D7D5B64DA3F3' -or
    [string]$catalog.source.loader -ne 'M1937.exe sub_453FE0') {
    throw 'Original actor dormant-field catalog identity is invalid.'
}

$layout = $catalog.layout
$dormantFields = @($layout.dormant_zero_fields)
if ([int]$layout.entity_format_version -ne 5 -or
    [int]$layout.serialized_runtime_field_count -ne 41 -or
    [int]$layout.runtime_destination_count -ne 41 -or
    $dormantFields.Count -ne 2 -or
    [int]$dormantFields[0].serialized_index -ne 19 -or
    [string]$dormantFields[0].name -ne 'UnknownRuntime21C' -or
    [string]$dormantFields[0].runtime_offset_hex -ne '0x21C' -or
    [int]$dormantFields[1].serialized_index -ne 30 -or
    [string]$dormantFields[1].name -ne 'UnknownRuntime274' -or
    [string]$dormantFields[1].runtime_offset_hex -ne '0x274' -or
    @($dormantFields | Where-Object {
        [string]$_.semantic_status -ne
            'unknown_no_supported_executable_consumer'
    }).Count -ne 0 -or
    [int]$layout.loader_discarded_tail.serialized_value_count -ne 24 -or
    [int]$layout.loader_discarded_tail.runtime_destination_count -ne 0 -or
    [string]$layout.loader_discarded_tail.preservation_policy -ne
        'retain_raw_values_for_audit_and_round_trip') {
    throw 'Version-5 SLIST dormant-field layout contract is invalid.'
}

$levels = @($catalog.levels)
$sceneTotal = 0
$extendedTotal = 0
if ($levels.Count -ne 12) {
    throw 'Actor dormant-field catalog must contain exactly twelve levels.'
}
for ($levelIndex = 0; $levelIndex -lt 12; ++$levelIndex) {
    $level = $levels[$levelIndex]
    $levelId = 'm{0:D3}' -f $levelIndex
    if ([string]$level.id -ne $levelId -or
        [string]$level.map_file -ne "1937$levelId.vwf" -or
        [string]$level.map_sha256 -notmatch '^[0-9A-F]{64}$' -or
        [int]$level.scene_entity_count -le 0 -or
        [int]$level.extended_data_entity_count -ne
            [int]$level.scene_entity_count -or
        [int]$level.unknown_runtime_21c_nonzero_entity_count -ne 0 -or
        [int]$level.unknown_runtime_274_nonzero_entity_count -ne 0 -or
        [int]$level.reserved_tail_nonzero_entity_count -ne 0 -or
        [int]$level.reserved_tail_nonzero_value_count -ne 0) {
        throw "$levelId dormant-field evidence is invalid."
    }
    $sceneTotal += [int]$level.scene_entity_count
    $extendedTotal += [int]$level.extended_data_entity_count
}
if ($sceneTotal -ne 19199 -or
    $extendedTotal -ne 19199 -or
    [int]$catalog.summary.level_count -ne 12 -or
    [int]$catalog.summary.scene_entity_count -ne $sceneTotal -or
    [int]$catalog.summary.extended_data_entity_count -ne $extendedTotal -or
    [int]$catalog.summary.unknown_runtime_21c_nonzero_entity_count -ne 0 -or
    [int]$catalog.summary.unknown_runtime_274_nonzero_entity_count -ne 0 -or
    [int]$catalog.summary.reserved_tail_nonzero_entity_count -ne 0 -or
    [int]$catalog.summary.reserved_tail_nonzero_value_count -ne 0) {
    throw 'Actor dormant-field summary changed unexpectedly.'
}

$materializedPaths = @(
    (Join-Path $GameDirectory 'M1937.exe'),
    (Join-Path $GameDirectory '1937Database.dbl')
)
foreach ($levelIndex in 0..11) {
    $materializedPaths += Join-Path `
        $GameDirectory `
        ('1937m{0:D3}.vwf' -f $levelIndex)
}
$hasMaterializedMod = @($materializedPaths | Where-Object {
    -not (Test-Path -LiteralPath $_ -PathType Leaf) -or
    (Get-Item -LiteralPath $_).Length -lt 100000
}).Count -eq 0
if ($hasMaterializedMod) {
    $temporaryPath = Join-Path `
        ([IO.Path]::GetTempPath()) `
        ('mission1937-actor-fields-' + [Guid]::NewGuid().ToString('N') +
            '.json')
    try {
        $resourceTool = Join-Path `
            $remakeRoot `
            'tools\ResourceTool\ResourceTool.csproj'
        dotnet run --project $resourceTool --configuration Release `
            --no-build -- actor-field-audit $GameDirectory $temporaryPath
        if ($LASTEXITCODE -ne 0) {
            throw "Actor-field audit generator failed with exit code $LASTEXITCODE."
        }
        if ((Get-CanonicalTextSha256 -LiteralPath $temporaryPath) -ne
            (Get-CanonicalTextSha256 -LiteralPath $CatalogPath)) {
            throw 'Actor dormant-field catalog is stale against the materialized MOD.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}
else {
    Write-Host (
        'Stable MOD binaries are not materialized; validated the committed ' +
        'machine-readable dormant-field contract without regeneration.')
}

Write-Host (
    'Original actor dormant-field audit passed: 19,199 version-5 actors, ' +
    'ext19/+0x21C and ext30/+0x274 zero in all twelve formal worlds, and ' +
    '460,776 loader-discarded tail values preserved and zero.')
