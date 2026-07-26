param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,

    [string]$OutputPath = '',

    [string]$Language = 'zh-Hans-CN'
)

$ErrorActionPreference = 'Stop'
$image = [IO.Path]::GetFullPath($ImagePath)
if (-not (Test-Path -LiteralPath $image -PathType Leaf)) {
    throw "Image does not exist: $image"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = [IO.Path]::ChangeExtension($image, '.ocr.txt')
}
$output = [IO.Path]::GetFullPath($OutputPath)

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

$script:asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object {
        $_.Name -eq 'AsTask' -and
        $_.IsGenericMethod -and
        $_.GetGenericArguments().Count -eq 1 -and
        $_.GetParameters().Count -eq 1 -and
        $_.ReturnType.IsGenericType
    } |
    Select-Object -First 1
if ($null -eq $script:asTask) {
    throw 'Could not locate the WinRT AsTask adapter.'
}

function Wait-WinRtResult {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Operation,

        [Parameter(Mandatory = $true)]
        [Type]$ResultType
    )

    $task = $script:asTask.MakeGenericMethod($ResultType).Invoke(
        $null,
        @($Operation))
    $task.Wait()
    return $task.Result
}

$file = Wait-WinRtResult `
    ([Windows.Storage.StorageFile]::GetFileFromPathAsync($image)) `
    ([Windows.Storage.StorageFile])
$stream = Wait-WinRtResult `
    ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) `
    ([Windows.Storage.Streams.IRandomAccessStream])

try {
    $decoder = Wait-WinRtResult `
        ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) `
        ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Wait-WinRtResult `
        ($decoder.GetSoftwareBitmapAsync()) `
        ([Windows.Graphics.Imaging.SoftwareBitmap])
    try {
        $recognizerLanguage = [Windows.Globalization.Language]::new($Language)
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage(
            $recognizerLanguage)
        if ($null -eq $engine) {
            throw "Windows OCR language is unavailable: $Language"
        }
        $result = Wait-WinRtResult `
            ($engine.RecognizeAsync($bitmap)) `
            ([Windows.Media.Ocr.OcrResult])
        [IO.File]::WriteAllText(
            $output,
            $result.Text + [Environment]::NewLine,
            [Text.UTF8Encoding]::new($false))
    }
    finally {
        $bitmap.Dispose()
    }
}
finally {
    $stream.Dispose()
}

Write-Output $output
