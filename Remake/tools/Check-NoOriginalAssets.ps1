[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$trackedFiles = @(git -c core.quotepath=false -C $repositoryRoot ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enumerate tracked files.'
}

$bannedExtensions = @(
    '.gfl', '.vwf', '.svt', '.sav', '.dbl', '.slf', '.si0',
    '.spr', '.spr1', '.tlg', '.tlg1', '.iblock', '.psd', '.wav',
    '.i64', '.idb', '.id0', '.id1', '.nam', '.til'
)
$bannedNames = @(
    'm1937.exe',
    '1937setup.exe',
    '1937resources.gfl',
    'intermedia.gfl',
    '1937intro.svt',
    'gamekinglogo.svt'
)
$bannedHeaders = @(
    'GFL (Game File Library)',
    'VWL1 Intuition Engine Virtual World File',
    'DBL1 Intuition Engine Database File',
    'SLF1 Intuition Engine Professional Sound Library',
    'SPR1 Intuition Engine Professional Sprite File',
    'TLG1 Intuition Engine Professional TileGroup File',
    'IBLOCK 1.0.0 Copyright U.M.E 2000'
)
$violations = [Collections.Generic.List[string]]::new()

foreach ($relativePath in $trackedFiles) {
    $forwardPath = $relativePath.Replace('\', '/')
    $normalized = $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $absolutePath = Join-Path $repositoryRoot $normalized
    $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
    $name = [IO.Path]::GetFileName($relativePath).ToLowerInvariant()

    # `git ls-files` also reports tracked paths deleted in the current worktree.
    # The guard validates files that would remain in the deliverable, so a pending
    # deletion must not fail before Git has staged or committed it.
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        continue
    }

    if ($bannedExtensions -contains $extension) {
        $violations.Add("Banned original extension: $relativePath")
    }
    if ($bannedNames -contains $name) {
        $violations.Add("Banned original filename: $relativePath")
    }
    if ($forwardPath -match '(^|/)raw/gfl(/|$)' -or $name -eq 'gfl-manifest.json') {
        $violations.Add("Generated original-resource import path: $relativePath")
    }
    $file = Get-Item -LiteralPath $absolutePath
    if ($file.Length -gt 25MB) {
        $violations.Add("Unexpected tracked file larger than 25 MiB: $relativePath")
    }

    if ($extension -eq '.zip') {
        $archive = [IO.Compression.ZipFile]::OpenRead($absolutePath)
        try {
            foreach ($entry in $archive.Entries) {
                $entryExtension = [IO.Path]::GetExtension($entry.FullName).ToLowerInvariant()
                $entryName = [IO.Path]::GetFileName($entry.FullName).ToLowerInvariant()
                if ($bannedExtensions -contains $entryExtension -or $bannedNames -contains $entryName) {
                    $violations.Add("Original asset-like entry inside ZIP: $relativePath -> $($entry.FullName)")
                }
                if ($forwardPath -match '^Patch/release/' -and $entryExtension -eq '.zip') {
                    $violations.Add("Nested archive inside release ZIP: $relativePath -> $($entry.FullName)")
                }
                if ($entry.Length -gt 0) {
                    $entryStream = $entry.Open()
                    try {
                        $entryBuffer = [byte[]]::new([Math]::Min(96, [int]$entry.Length))
                        $entryRead = $entryStream.Read($entryBuffer, 0, $entryBuffer.Length)
                        $entryHeader = [Text.Encoding]::ASCII.GetString($entryBuffer, 0, $entryRead)
                        foreach ($bannedHeader in $bannedHeaders) {
                            if ($entryHeader.StartsWith($bannedHeader, [StringComparison]::Ordinal)) {
                                $violations.Add(
                                    "Original resource signature inside ZIP: $relativePath -> $($entry.FullName)")
                            }
                        }
                        if (($entryRead -ge 12 -and $entryHeader.StartsWith('RIFF') -and
                                $entryHeader.Substring(8, 4) -eq 'WAVE') -or
                            ($entryRead -ge 4 -and $entryHeader.StartsWith('8BPS'))) {
                            $violations.Add(
                                "Original standard-asset signature inside ZIP: $relativePath -> $($entry.FullName)")
                        }
                    }
                    finally {
                        $entryStream.Dispose()
                    }
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }

    if ($file.Length -gt 0) {
        $stream = [IO.File]::OpenRead($absolutePath)
        try {
            $buffer = [byte[]]::new([Math]::Min(96, [int]$file.Length))
            $read = $stream.Read($buffer, 0, $buffer.Length)
            $header = [Text.Encoding]::ASCII.GetString($buffer, 0, $read)
            foreach ($bannedHeader in $bannedHeaders) {
                if ($header.StartsWith($bannedHeader, [StringComparison]::Ordinal)) {
                    $violations.Add("Original resource signature detected: $relativePath")
                }
            }
            if (($read -ge 12 -and $header.StartsWith('RIFF') -and $header.Substring(8, 4) -eq 'WAVE') -or
                ($read -ge 4 -and $header.StartsWith('8BPS'))) {
                $violations.Add("Original standard-asset signature detected: $relativePath")
            }
        }
        finally {
            $stream.Dispose()
        }
    }

    if ($name -eq 'manifest.json' -and $file.Length -gt 0) {
        $manifestPrefix = [Text.Encoding]::UTF8.GetString(
            [IO.File]::ReadAllBytes($absolutePath),
            0,
            [Math]::Min(4096, [int]$file.Length))
        if ($manifestPrefix.Contains('Mission1937.Remake.ResourceTool')) {
            $violations.Add("Generated original-resource manifest detected: $relativePath")
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error $_ }
    throw "Original asset guard found $($violations.Count) violation(s)."
}

Write-Host "Original asset guard passed for $($trackedFiles.Count) tracked or pending files."
