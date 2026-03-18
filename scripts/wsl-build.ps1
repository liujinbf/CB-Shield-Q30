param(
    [ValidateSet("bootstrap", "prepare", "build", "shell")]
    [string]$Action = "build",
    [string]$Profile = "stable",
    [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"

function Convert-ToWslPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WindowsPath
    )

    $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
    $drive = $fullPath.Substring(0, 1).ToLowerInvariant()
    $rest = $fullPath.Substring(2).Replace('\', '/')
    return "/mnt/$drive$rest"
}

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandText
    )

    & wsl.exe -d $Distro -- bash -lc $CommandText
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed"
    }
}

function Get-WslDistros {
    $raw = & wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    return @(
        $raw -split "`r?`n" |
        ForEach-Object { ($_ -replace "`0", "").Trim() } |
        Where-Object { $_ }
    )
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$wslRepoRoot = Convert-ToWslPath -WindowsPath $repoRoot
$distros = Get-WslDistros

if (-not ($distros -contains $Distro)) {
    $available = if ($distros.Count -gt 0) { $distros -join ", " } else { "none" }
    throw "WSL distro '$Distro' not found. Available: $available"
}

switch ($Action) {
    "bootstrap" {
        Invoke-WslCommand "cd '$wslRepoRoot' && bash scripts/wsl-bootstrap.sh"
    }
    "prepare" {
        Invoke-WslCommand "cd '$wslRepoRoot' && bash scripts/prepare-openwrt.sh .work/openwrt '$Profile' && bash scripts/package-preflight.sh .work/openwrt"
    }
    "build" {
        Invoke-WslCommand "cd '$wslRepoRoot' && bash scripts/local-build.sh '$Profile'"
    }
    "shell" {
        Invoke-WslCommand "cd '$wslRepoRoot' && exec bash"
    }
}
