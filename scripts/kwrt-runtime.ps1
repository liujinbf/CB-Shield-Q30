param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("build")]
    [string]$Action
)

$ErrorActionPreference = "Stop"

function Find-GitBash {
    $candidates = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Git Bash not found. Please install Git for Windows."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bashExe = Find-GitBash

switch ($Action) {
    "build" {
        & $bashExe (Join-Path $scriptDir "build-kwrt-runtime-bundle.sh")
        if ($LASTEXITCODE -ne 0) {
            throw "Kwrt runtime bundle build failed"
        }
    }
}
