param(
    [switch]$SkipGeneratedCheck
)

$ErrorActionPreference = 'Stop'
$sdkRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $sdkRoot '..'))
$catalog = Get-Content -LiteralPath (
    Join-Path $sdkRoot 'address-catalog.json') -Raw -Encoding UTF8 |
    ConvertFrom-Json

if (-not $SkipGeneratedCheck) {
    & (Join-Path $PSScriptRoot 'Generate-SdkArtifacts.ps1') -Check
}

$known = @{}
foreach ($address in $catalog.addresses) {
    $numeric = [Convert]::ToUInt32(
        ([string]$address.rva).Substring(2), 16)
    if ($known.ContainsKey($numeric)) {
        throw "Duplicate RVA in address catalog: $($address.rva)"
    }
    $known[$numeric] = [string]$address.name
}

$allowed = @(
    [IO.Path]::GetFullPath((Join-Path $sdkRoot 'include\M1937SDK\Addresses.hpp')),
    [IO.Path]::GetFullPath((Join-Path $sdkRoot 'include\M1937SDK\CrtRandom.hpp')),
    [IO.Path]::GetFullPath((Join-Path $sdkRoot 'include\M1937SDK\MissionRoutes.hpp')),
    [IO.Path]::GetFullPath((Join-Path $sdkRoot 'generated\M1937Addresses.cs')),
    [IO.Path]::GetFullPath((Join-Path $sdkRoot 'generated\M1937MissionRoutes.cs'))
)
$violations = [Collections.Generic.List[string]]::new()
$extensions = @('.cpp', '.cxx', '.cc', '.hpp', '.h', '.cs', '.ps1')
foreach ($root in @(
    (Join-Path $repositoryRoot 'Patch'),
    (Join-Path $repositoryRoot 'MapEditor'),
    (Join-Path $repositoryRoot 'SDK'))) {
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File) {
        if ($extensions -notcontains $file.Extension.ToLowerInvariant() -or
            $allowed -contains $file.FullName -or
            $file.FullName.StartsWith(
                (Join-Path $sdkRoot 'tools'),
                [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
            $lineNumber++
            foreach ($match in [regex]::Matches(
                $line, '(?<![0-9A-Fa-f])0x[0-9A-Fa-f]{5,8}(?![0-9A-Fa-f])')) {
                $numeric = [Convert]::ToUInt32(
                    $match.Value.Substring(2), 16)
                if (-not $known.ContainsKey($numeric)) { continue }
                $relative = $file.FullName.Substring(
                    $repositoryRoot.Length).TrimStart('\')
                $violations.Add(
                    "$relative`:$lineNumber duplicates " +
                    "$($known[$numeric]) ($($match.Value))")
            }
        }
    }
}

if ($violations.Count -gt 0) {
    throw "Known engine RVAs must come from generated SDK constants:`n$(
        $violations -join "`n")"
}
Write-Host (
    "SDK single-source guard passed for {0} unique engine addresses." -f
    $known.Count)
