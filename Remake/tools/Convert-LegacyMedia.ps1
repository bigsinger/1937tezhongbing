[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameDirectory,

    [string]$ConvertedDirectory = (Join-Path $PSScriptRoot '..\LocalAssets\converted'),

    [string]$FfmpegExecutable,

    [string[]]$MediaId = @('logo', 'historical_intro'),

    [switch]$IncludeUnreferencedBonusVideos
)

$ErrorActionPreference = 'Stop'
$gameRoot = (Resolve-Path -LiteralPath $GameDirectory).Path
$convertedRoot = [IO.Path]::GetFullPath($ConvertedDirectory)
if ($convertedRoot.StartsWith(
        $gameRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ConvertedDirectory must not be inside the original game directory.'
}

if ([string]::IsNullOrWhiteSpace($FfmpegExecutable)) {
    $ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($null -ne $ffmpegCommand) {
        $FfmpegExecutable = $ffmpegCommand.Source
    }
}
if ([string]::IsNullOrWhiteSpace($FfmpegExecutable)) {
    throw 'FFmpeg was not found. Pass -FfmpegExecutable with an FFmpeg 6 or newer executable.'
}
$ffmpeg = (Resolve-Path -LiteralPath $FfmpegExecutable).Path

$definitions = [ordered]@{
    logo = @{
        source = 'GamekingLogo.svt'; output = 'logo.ogv'; role = 'publisher_logo'
        filter = 'fps=30,setsar=1'
    }
    historical_intro = @{
        source = '1937Intro.svt'; output = 'historical_intro.ogv'; role = 'historical_intro'
        # The original DirectDraw path doubled the 640x240 MPEG field vertically.
        filter = 'fps=30,scale=640:480:flags=lanczos,setsar=1'
    }
    bonus_013 = @{
        source = '1937m013.vwf'; output = 'bonus_013.ogv'; role = 'unreferenced_bonus'
        filter = 'fps=25,setsar=1'
    }
    bonus_014 = @{
        source = '1937m014.vwf'; output = 'bonus_014.ogv'; role = 'unreferenced_bonus'
        filter = 'fps=25,setsar=1'
    }
    bonus_015 = @{
        source = '1937m015.vwf'; output = 'bonus_015.ogv'; role = 'unreferenced_bonus'
        filter = 'fps=25,setsar=1'
    }
}

$requested = [Collections.Generic.List[string]]::new()
foreach ($id in $MediaId) {
    if (-not $definitions.Contains($id)) {
        throw "Unknown media id '$id'."
    }
    if (-not $requested.Contains($id)) {
        $requested.Add($id)
    }
}
if ($IncludeUnreferencedBonusVideos) {
    foreach ($id in @('bonus_013', 'bonus_014', 'bonus_015')) {
        if (-not $requested.Contains($id)) {
            $requested.Add($id)
        }
    }
}

$videoRoot = Join-Path $convertedRoot 'media\video'
New-Item -ItemType Directory -Path $videoRoot -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
foreach ($id in $requested) {
    $definition = $definitions[$id]
    if ($definition.role -eq 'unreferenced_bonus' -and -not $IncludeUnreferencedBonusVideos) {
        throw "'$id' is unreferenced bonus media. Pass -IncludeUnreferencedBonusVideos explicitly."
    }
    $sourcePath = Join-Path $gameRoot $definition.source
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Missing original media: $sourcePath"
    }
    $outputPath = Join-Path $videoRoot $definition.output
    & $ffmpeg -nostdin -y -hide_banner -loglevel warning `
        -i $sourcePath -map '0:v:0' -map '0:a:0?' `
        -vf $definition.filter -c:v libtheora -q:v 7 `
        -c:a libvorbis -q:a 5 -ar 44100 -ac 2 $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw "FFmpeg failed for '$id' with exit code $LASTEXITCODE."
    }
    $results.Add([ordered]@{
        id = $id
        role = $definition.role
        source_name = $definition.source
        source_sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        output_relative_path = ('media/video/' + $definition.output)
        output_sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash
        output_bytes = (Get-Item -LiteralPath $outputPath).Length
    })
}

$manifestPath = Join-Path $convertedRoot 'media-transcode-manifest.json'
[ordered]@{
    schema_version = 1
    ffmpeg = $ffmpeg
    generated_utc = [DateTime]::UtcNow.ToString('O')
    media = $results
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Host "Converted $($results.Count) legacy media file(s)."
Write-Host "Local-only manifest: $manifestPath"
