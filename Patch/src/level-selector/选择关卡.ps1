param(
    [ValidateRange(0, 12)]
    [int]$Level = 0,
    [switch]$StartImmediately
)

$ErrorActionPreference = 'Stop'
$gameDirectory = [IO.Path]::GetFullPath($PSScriptRoot)
$gameExecutable = Join-Path $gameDirectory 'M1937.exe'
$catalogPath = Join-Path $gameDirectory ([char]0x5173 + [char]0x5361 + [char]0x540D + [char]0x79F0 + '.json')
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Start-OriginalMission {
    param([ValidateRange(1, 12)][int]$MissionNumber)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gameExecutable
    $startInfo.WorkingDirectory = $gameDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.EnvironmentVariables['M1937_START_LEVEL'] = [string]$MissionNumber
    [System.Diagnostics.Process]::Start($startInfo) | Out-Null
}

if (-not (Test-Path -LiteralPath $gameExecutable -PathType Leaf)) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        ($catalog.missing_executable -f $gameDirectory),
        $catalog.window_title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 2
}

if ($StartImmediately) {
    if ($Level -lt 1 -or $Level -gt 12) {
        throw 'StartImmediately requires Level in the range 1..12.'
    }
    Start-OriginalMission -MissionNumber $Level
    exit 0
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = $catalog.window_title
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(570, 410)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = $catalog.heading
$title.Location = New-Object System.Drawing.Point(24, 18)
$title.Size = New-Object System.Drawing.Size(520, 30)
$title.Font = New-Object System.Drawing.Font(
    'Microsoft YaHei UI',
    13,
    [Drawing.FontStyle]::Bold
)
$form.Controls.Add($title)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = $catalog.hint
$hint.Location = New-Object System.Drawing.Point(26, 52)
$hint.Size = New-Object System.Drawing.Size(520, 24)
$form.Controls.Add($hint)

for ($index = 0; $index -lt $catalog.missions.Count; $index++) {
    $mission = $catalog.missions[$index]
    $column = $index % 2
    $row = [Math]::Floor($index / 2)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = ($catalog.button_template -f $mission.number, $mission.title)
    $button.Tag = $mission.number
    $button.Location = New-Object System.Drawing.Point(
        (26 + $column * 265),
        (88 + $row * 46)
    )
    $button.Size = New-Object System.Drawing.Size(250, 36)
    $button.Add_Click({
        try {
            Start-OriginalMission -MissionNumber ([int]$this.Tag)
            $form.Close()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                $catalog.launch_failed,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })
    $form.Controls.Add($button)
}

$close = New-Object System.Windows.Forms.Button
$close.Text = $catalog.cancel
$close.Location = New-Object System.Drawing.Point(444, 370)
$close.Size = New-Object System.Drawing.Size(100, 30)
$close.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $close
$form.Controls.Add($close)

[void]$form.ShowDialog()
