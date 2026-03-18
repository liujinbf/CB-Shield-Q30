param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("prepare", "overlay", "defaults", "verify", "request", "acceptance", "buildremote")]
    [string]$Action,

    [string]$ImagePath,
    [string]$OutputPath,
    [string]$ProfilePath,
    [ValidateSet("summary", "json", "checklist")]
    [string]$RequestFormat = "summary",
    [string]$OverlayPath,
    [string]$CookieHeader,
    [string]$CookieFile,
    [string]$UploadNonce,
    [string]$RemoteOverlayPath,
    [switch]$InlineDefaults,
    [switch]$VerifyAfterBuild,
    [switch]$SkipSmoke,
    [switch]$Stdout
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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

function Run-BashScript {
    param(
        [string]$ScriptPath,
        [string[]]$ScriptArgs = @()
    )

    $bashExe = Find-GitBash
    & $bashExe $ScriptPath @ScriptArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Script failed: $ScriptPath"
    }
}

switch ($Action) {
    "prepare" {
        $args = @()
        if ($SkipSmoke) {
            $args += "--skip-smoke"
        }
        Run-BashScript -ScriptPath (Join-Path $scriptDir "prepare-openwrtai-upload.sh") -ScriptArgs $args
    }

    "overlay" {
        Run-BashScript -ScriptPath (Join-Path $scriptDir "build-openwrtai-overlay.sh")
    }

    "defaults" {
        $args = @()
        if ($Stdout) {
            $args += "--stdout"
        } elseif ($OutputPath) {
            $args += @("--output", $OutputPath)
        }
        Run-BashScript -ScriptPath (Join-Path $scriptDir "render-openwrtai-defaults.sh") -ScriptArgs $args
    }

    "verify" {
        if (-not $ImagePath) {
            throw "verify requires -ImagePath"
        }

        & python (Join-Path $scriptDir "verify-openwrtai-image.py") $ImagePath
        if ($LASTEXITCODE -ne 0) {
            throw "Image verification failed: $ImagePath"
        }
    }

    "request" {
        $args = @("--format", $RequestFormat)
        if ($ProfilePath) {
            $args += @("--profile", $ProfilePath)
        }
        if ($OverlayPath) {
            $args += @("--overlay", $OverlayPath)
        }
        if ($InlineDefaults) {
            $args += "--defaults-inline"
        }
        & python (Join-Path $scriptDir "render-openwrtai-request.py") @args
        if ($LASTEXITCODE -ne 0) {
            throw "Request rendering failed"
        }
    }

    "acceptance" {
        $args = @()
        if ($ProfilePath) {
            $args += @("--profile", $ProfilePath)
        }
        & python (Join-Path $scriptDir "render-postflash-checklist.py") @args
        if ($LASTEXITCODE -ne 0) {
            throw "Acceptance checklist rendering failed"
        }
    }

    "buildremote" {
        if ((-not $CookieHeader) -and (-not $CookieFile)) {
            throw "buildremote requires -CookieHeader or -CookieFile"
        }

        $args = @("--defaults-inline")
        if ($CookieHeader) {
            $args += @("--cookie-header", $CookieHeader)
        }
        if ($CookieFile) {
            $args += @("--cookie-file", $CookieFile)
        }
        if ($ProfilePath) {
            $args += @("--profile", $ProfilePath)
        }
        if ($RemoteOverlayPath) {
            $args += @("--overlay-remote", $RemoteOverlayPath)
        } else {
            if (-not $UploadNonce) {
                throw "buildremote requires -UploadNonce or -RemoteOverlayPath"
            }
            $args += @("--upload-nonce", $UploadNonce)
            if ($OverlayPath) {
                $args += @("--overlay-file", $OverlayPath)
            }
        }
        if ($VerifyAfterBuild) {
            $args += "--verify"
        }

        & python (Join-Path $scriptDir "openwrtai-build.py") @args
        if ($LASTEXITCODE -ne 0) {
            throw "Remote build failed"
        }
    }
}
