param(
    [string]$Port = "COM3",
    [int]$BaudRate = 115200,
    [int]$DurationSec = 60,
    [string]$OutFile = "serial.log"
)

$ErrorActionPreference = "Stop"

$sp = New-Object System.IO.Ports.SerialPort $Port, $BaudRate, 'None', 8, 'One'
$sp.ReadTimeout = 500
$sp.NewLine = "`n"

try {
    $sp.Open()
    Write-Host "[serial] Opened $Port @ $BaudRate"
    $start = Get-Date
    $end = $start.AddSeconds($DurationSec)
    $buffer = New-Object System.Text.StringBuilder

    while ((Get-Date) -lt $end) {
        try {
            $chunk = $sp.ReadExisting()
            if ($chunk) {
                [void]$buffer.Append($chunk)
                Write-Output $chunk
            }
        } catch {
            Start-Sleep -Milliseconds 50
        }
        Start-Sleep -Milliseconds 100
    }

    $text = $buffer.ToString()
    if ($OutFile) {
        $dir = Split-Path -Parent $OutFile
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $text | Out-File -FilePath $OutFile -Encoding utf8
        Write-Host "[serial] Saved to $OutFile"
    }
} finally {
    if ($sp.IsOpen) {
        $sp.Close()
    }
    Write-Host "[serial] Closed $Port"
}
