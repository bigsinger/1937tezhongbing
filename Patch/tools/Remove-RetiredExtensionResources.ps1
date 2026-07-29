[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$TemporaryRoot = 'E:\1937'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..'
}
$repository = [IO.Path]::GetFullPath($RepositoryRoot)
$mod = [IO.Path]::GetFullPath((Join-Path $repository 'Mod'))
$resource = Join-Path $mod '1937Resources.GFL'
$index = Join-Path $mod 'InterMedia.GFL'
$project = Join-Path $repository (
    'Remake\tools\ResourceTool\ResourceTool.csproj')

$allowedTemporaryRoot =
    [IO.Path]::GetFullPath($TemporaryRoot).TrimEnd('\')
$temporary = [IO.Path]::GetFullPath((Join-Path $allowedTemporaryRoot (
    'retired-extension-resources-' + [Guid]::NewGuid().ToString('N'))))
if (-not (($temporary.TrimEnd('\') + '\').StartsWith(
        $allowedTemporaryRoot + '\',
        [StringComparison]::OrdinalIgnoreCase))) {
    throw "Unsafe temporary path: $temporary"
}
foreach ($required in @($resource, $index, $project)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required file is missing: $required"
    }
}

$outputResource = Join-Path $temporary '1937Resources.GFL'
$outputIndex = Join-Path $temporary 'InterMedia.GFL'
$token = [Guid]::NewGuid().ToString('N')
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
    dotnet run --project $project -c Release -- `
        prune-retired-briefings `
        $resource `
        $index `
        $outputResource `
        $outputIndex
    if ($LASTEXITCODE -ne 0) {
        throw "Resource pruning failed with exit code $LASTEXITCODE."
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

    $listing = & dotnet run --project $project -c Release -- `
        list-gfl $resource $index --all
    if ($LASTEXITCODE -ne 0) {
        throw "Post-prune GFL validation failed with exit code $LASTEXITCODE."
    }
    if (($listing -join "`n") -match 'Brief_01[234]\.psd') {
        throw 'A retired extension briefing is still present after pruning.'
    }
    if (-not (($listing -join "`n") -match 'Total:\s+1394 entries')) {
        throw 'The pruned GFL does not contain exactly 1,394 entries.'
    }

    [pscustomobject]@{
        ResourceSha256 = (
            Get-FileHash -LiteralPath $resource -Algorithm SHA256).Hash
        IndexSha256 = (
            Get-FileHash -LiteralPath $index -Algorithm SHA256).Hash
        EntryCount = 1394
        Removed = @(
            'Brief_012.psd',
            'Brief_013.psd',
            'Brief_014.psd')
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
            $outputResource,
            $outputIndex,
            $pendingResource,
            $pendingIndex,
            $backupResource,
            $backupIndex)) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            [IO.File]::Delete([IO.Path]::GetFullPath($file))
        }
    }
    if (Test-Path -LiteralPath $temporary -PathType Container) {
        $resolved = [IO.Path]::GetFullPath($temporary)
        if (-not (($resolved.TrimEnd('\') + '\').StartsWith(
                $allowedTemporaryRoot + '\',
                [StringComparison]::OrdinalIgnoreCase))) {
            throw "Refusing to remove unsafe temporary path: $resolved"
        }
        [IO.Directory]::Delete($resolved, $false)
    }
}
