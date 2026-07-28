param(
    [string]$RepositoryRoot = '',
    [string]$PreviewDirectory = 'E:\1937\text-briefing-previews'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..'
}
$repository = [IO.Path]::GetFullPath($RepositoryRoot)
$mod = Join-Path $repository 'Mod'
$catalog = Get-ChildItem -LiteralPath $mod -Filter '*.json' -File |
    Where-Object {
        try {
            $candidate = Get-Content -LiteralPath $_.FullName `
                -Raw -Encoding UTF8 | ConvertFrom-Json
            $null -ne $candidate.missions -and
                @($candidate.missions).Count -eq 15 -and
                $null -ne $candidate.window_title
        }
        catch {
            $false
        }
    } |
    Select-Object -First 1 -ExpandProperty FullName
if ([string]::IsNullOrWhiteSpace($catalog)) {
    throw 'The 15-level briefing catalog was not found in Mod.'
}
$resource = Join-Path $mod '1937Resources.GFL'
$index = Join-Path $mod 'InterMedia.GFL'
$project = Join-Path $repository (
    'Remake\tools\ResourceTool\ResourceTool.csproj')
$allowedTemporaryRoot = [IO.Path]::GetFullPath('E:\1937').TrimEnd('\')
$preview = [IO.Path]::GetFullPath($PreviewDirectory)
if (-not (($preview.TrimEnd('\') + '\').StartsWith(
        $allowedTemporaryRoot + '\',
        [StringComparison]::OrdinalIgnoreCase))) {
    throw "PreviewDirectory must stay under E:\1937: $preview"
}
foreach ($required in @($catalog, $resource, $index, $project)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required file is missing: $required"
    }
}

$token = [Guid]::NewGuid().ToString('N')
$temporary = Join-Path $allowedTemporaryRoot (
    'text-briefing-update-' + $token)
$outputResource = Join-Path $temporary '1937Resources.GFL'
$outputIndex = Join-Path $temporary 'InterMedia.GFL'
$pendingResource = Join-Path $mod (
    '1937Resources.GFL.pending-' + $token)
$pendingIndex = Join-Path $mod (
    'InterMedia.GFL.pending-' + $token)
$backupResource = Join-Path $mod (
    '1937Resources.GFL.backup-' + $token)
$backupIndex = Join-Path $mod (
    'InterMedia.GFL.backup-' + $token)
$resourceReplaced = $false
$indexReplaced = $false

try {
    [IO.Directory]::CreateDirectory($temporary) | Out-Null
    [IO.Directory]::CreateDirectory($preview) | Out-Null

    dotnet build $project -c Release --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "ResourceTool build failed with exit code $LASTEXITCODE."
    }
    dotnet run --project $project -c Release --no-build -- `
        install-text-briefings `
        $catalog `
        $resource `
        $index `
        $outputResource `
        $outputIndex `
        $preview
    if ($LASTEXITCODE -ne 0) {
        throw "Text briefing generation failed with exit code $LASTEXITCODE."
    }
    foreach ($generated in @($outputResource, $outputIndex)) {
        if (-not (Test-Path -LiteralPath $generated -PathType Leaf) -or
            (Get-Item -LiteralPath $generated).Length -le 0) {
            throw "Generated GFL is missing or empty: $generated"
        }
    }

    Copy-Item -LiteralPath $outputResource `
        -Destination $pendingResource -Force
    Copy-Item -LiteralPath $outputIndex `
        -Destination $pendingIndex -Force

    [IO.File]::Replace(
        $pendingResource,
        $resource,
        $backupResource,
        $true)
    $resourceReplaced = $true
    [IO.File]::Replace(
        $pendingIndex,
        $index,
        $backupIndex,
        $true)
    $indexReplaced = $true

    [pscustomobject]@{
        Catalog = $catalog
        ResourceSha256 = (
            Get-FileHash -LiteralPath $resource -Algorithm SHA256).Hash
        IndexSha256 = (
            Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash
        PreviewDirectory = $preview
        BriefingCount = @(
            Get-ChildItem -LiteralPath $preview `
                -Filter 'mission-*.png' -File).Count
    }
}
catch {
    if ($resourceReplaced -and
        (Test-Path -LiteralPath $backupResource -PathType Leaf)) {
        Copy-Item -LiteralPath $backupResource `
            -Destination $resource -Force
    }
    if ($indexReplaced -and
        (Test-Path -LiteralPath $backupIndex -PathType Leaf)) {
        Copy-Item -LiteralPath $backupIndex `
            -Destination $index -Force
    }
    throw
}
finally {
    foreach ($file in @(
            $pendingResource,
            $pendingIndex,
            $backupResource,
            $backupIndex)) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force
        }
    }
    if (Test-Path -LiteralPath $temporary -PathType Container) {
        $resolvedTemporary = [IO.Path]::GetFullPath($temporary)
        if (($resolvedTemporary.TrimEnd('\') + '\').StartsWith(
                $allowedTemporaryRoot + '\',
                [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
        }
    }
}
