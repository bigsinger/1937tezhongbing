param(
    [Parameter(Mandatory)]
    [string]$ImagePath,
    [string]$OutputPath = '',
    [string]$Language = 'zh-CN'
)

$ErrorActionPreference = 'Stop'
$ImagePath = [IO.Path]::GetFullPath($ImagePath)
if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
    throw "Image does not exist: $ImagePath"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = $ImagePath + '.ocr.txt'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime]
[void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]

function Await-WindowsRuntimeOperation {
    param(
        [Parameter(Mandatory)]$Operation,
        [Parameter(Mandatory)][Type]$ResultType)
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethod -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1
    if ($null -eq $method) {
        throw 'Windows Runtime AsTask adapter is unavailable.'
    }
    $task = $method.MakeGenericMethod($ResultType).Invoke(
        $null, @($Operation))
    $task.Wait()
    return $task.Result
}

$ocrLanguage = [Windows.Globalization.Language]::new($Language)
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage(
    $ocrLanguage)
if ($null -eq $engine) {
    throw "Windows OCR language is not installed: $Language"
}
$file = Await-WindowsRuntimeOperation `
    ([Windows.Storage.StorageFile]::GetFileFromPathAsync($ImagePath)) `
    ([Windows.Storage.StorageFile])
$stream = Await-WindowsRuntimeOperation `
    ($file.OpenReadAsync()) `
    ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
try {
    $decoder = Await-WindowsRuntimeOperation `
        ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) `
        ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap = Await-WindowsRuntimeOperation `
        ($decoder.GetSoftwareBitmapAsync()) `
        ([Windows.Graphics.Imaging.SoftwareBitmap])
    try {
        $result = Await-WindowsRuntimeOperation `
            ($engine.RecognizeAsync($bitmap)) `
            ([Windows.Media.Ocr.OcrResult])
        [IO.Directory]::CreateDirectory(
            [IO.Path]::GetDirectoryName($OutputPath)) | Out-Null
        $result.Text | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        [pscustomobject]@{
            Image = $ImagePath
            Text = $OutputPath
            Characters = $result.Text.Length
            Uploaded = $false
        }
    }
    finally {
        $bitmap.Dispose()
    }
}
finally {
    $stream.Dispose()
}
