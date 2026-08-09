param(
    [string]$GameRoot = (Join-Path $PSScriptRoot '..\game'),
    [string]$WhitelistPath = (Join-Path $PSScriptRoot 'localization-hardcoded-whitelist-v1.json'),
    [switch]$RefreshWhitelist,
    [string]$JsonOutput = ''
)

$ErrorActionPreference = 'Stop'
$game = [IO.Path]::GetFullPath($GameRoot)
$catalogRoot = Join-Path $game 'data\localization'
$catalogPaths = @{
    zh_CN = Join-Path $catalogRoot 'zh_CN.json'
    en = Join-Path $catalogRoot 'en.json'
}

function Read-Catalog([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Localization catalog is missing: $Path"
    }
    $parsed = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $result = @{}
    foreach ($property in $parsed.PSObject.Properties) {
        if ($property.Name -notmatch '^[A-Z][A-Z0-9_]+$') {
            throw "Invalid localization key '$($property.Name)' in $Path"
        }
        if ($property.Value -isnot [string]) {
            throw "Localization value '$($property.Name)' is not text in $Path"
        }
        $result[$property.Name] = [string]$property.Value
    }
    return $result
}

function Placeholder-Signature([string]$Value) {
    $withoutEscapedPercent = $Value -replace '%%', ''
    return @([regex]::Matches(
        $withoutEscapedPercent,
        '%(?:[0-9]+\$)?[-+0 #]*(?:[0-9]+|\*)?(?:\.(?:[0-9]+|\*))?[diouxXeEfFgGsc]'
    ) | ForEach-Object { $_.Value.Substring($_.Value.Length - 1).ToLowerInvariant() })
}

function Stable-Hash([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))
        ) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Find-HardcodedText {
    $records = New-Object System.Collections.Generic.List[object]
    $literalPattern = [regex]'"[^"\r\n]*"'
    Get-ChildItem -LiteralPath (Join-Path $game 'scripts') -Recurse -Filter '*.gd' |
        Where-Object { $_.FullName -notmatch '[\\/]generated[\\/]' } |
        ForEach-Object {
            $file = $_
            $relative = $file.FullName.Substring($game.Length + 1).Replace('\', '/')
            $lineNumber = 0
            foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
                $lineNumber++
                foreach ($match in $literalPattern.Matches($line)) {
                    if ($match.Value -notmatch '[\u4E00-\u9FFF]') { continue }
                    $identity = "$relative|$($match.Value)"
                    $records.Add([pscustomobject][ordered]@{
                        file = $relative
                        line = $lineNumber
                        literal_sha256 = Stable-Hash $identity
                        reason = 'legacy_or_editorial_source_baseline'
                    })
                }
            }
        }
    return @($records | Sort-Object file, literal_sha256 -Unique)
}

$zh = Read-Catalog $catalogPaths.zh_CN
$en = Read-Catalog $catalogPaths.en
$failures = New-Object System.Collections.Generic.List[string]
$allKeys = @($zh.Keys + $en.Keys | Sort-Object -Unique)
foreach ($key in $allKeys) {
    if (-not $zh.ContainsKey($key)) { $failures.Add("zh_CN is missing $key") }
    if (-not $en.ContainsKey($key)) { $failures.Add("en is missing $key") }
    if ($zh.ContainsKey($key) -and $en.ContainsKey($key)) {
        $left = @(Placeholder-Signature $zh[$key]) -join ','
        $right = @(Placeholder-Signature $en[$key]) -join ','
        if ($left -ne $right) {
            $failures.Add("placeholder mismatch for ${key}: zh=[$left] en=[$right]")
        }
    }
}

$hardcoded = @(Find-HardcodedText)
if ($RefreshWhitelist) {
    $document = [ordered]@{
        schema_version = 1
        purpose = 'Freeze reviewed pre-localization legacy/editorial string literals; new player-visible text must use localization keys.'
        entries = $hardcoded
    }
    $directory = Split-Path -Parent ([IO.Path]::GetFullPath($WhitelistPath))
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $document | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $WhitelistPath -Encoding UTF8
}

$allowed = @{}
if (Test-Path -LiteralPath $WhitelistPath -PathType Leaf) {
    $whitelist = Get-Content -LiteralPath $WhitelistPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($whitelist.entries)) {
        $allowed[[string]$entry.literal_sha256] = $true
    }
}
foreach ($entry in $hardcoded) {
    if (-not $allowed.ContainsKey([string]$entry.literal_sha256)) {
        $failures.Add(
            "unlocalized CJK literal: $($entry.file):$($entry.line) [$($entry.literal_sha256)]"
        )
    }
}

$result = [ordered]@{
    schema_version = 1
    ok = $failures.Count -eq 0
    catalog_key_count = $allKeys.Count
    reviewed_literal_count = $hardcoded.Count
    failures = @($failures)
}
if ($JsonOutput) {
    $output = [IO.Path]::GetFullPath($JsonOutput)
    [IO.Directory]::CreateDirectory((Split-Path -Parent $output)) | Out-Null
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $output -Encoding UTF8
}
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host "Localization gate passed: $($allKeys.Count) keys, $($hardcoded.Count) reviewed legacy/editorial literals."
