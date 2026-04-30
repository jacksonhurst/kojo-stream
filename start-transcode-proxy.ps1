param(
    [int]$Port = 8977,
    [string]$HostAddress = "0.0.0.0"
)

$ErrorActionPreference = "Stop"

function Pause-BeforeExit {
    Write-Host ""
    Read-Host "Press Enter to close"
}

try {
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Host "Python was not found on PATH."
        Write-Host "Install Python 3, then run this script again."
        Write-Host "On Windows, one option is: winget install Python.Python.3.13"
        Pause-BeforeExit
        exit 1
    }

    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Write-Host "FFmpeg was not found on PATH."
        Write-Host "Install FFmpeg first, then run this script again."
        Write-Host ""
        Write-Host "Recommended Windows install command:"
        Write-Host "  winget install Gyan.FFmpeg"
        Write-Host ""
        Write-Host "After installing, close and reopen PowerShell so PATH refreshes."
        Pause-BeforeExit
        exit 1
    }

    $scriptPath = Join-Path $PSScriptRoot "tools\kojostream_transcode_proxy.py"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Missing proxy script: $scriptPath"
    }

    $lanIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.PrefixOrigin -ne "WellKnown"
        } |
        Select-Object -ExpandProperty IPAddress

    Write-Host "Starting KojoStream transcode proxy on $HostAddress`:$Port"
    if ($lanIps) {
        Write-Host "Use one of these URLs in Roku Settings > Transcode Server:"
        foreach ($ip in $lanIps) {
            Write-Host "  http://$ip`:$Port"
        }
    } else {
        Write-Host "Use your PC's LAN IP in Roku Settings > Transcode Server, for example:"
        Write-Host "  http://192.168.1.25:$Port"
    }
    Write-Host ""
    Write-Host "Leave this PowerShell window open while watching transcoded channels."
    Write-Host ""

    python $scriptPath --host $HostAddress --port $Port
} catch {
    Write-Host "Could not start the KojoStream transcode proxy."
    Write-Host $_.Exception.Message
    Pause-BeforeExit
    exit 1
}
