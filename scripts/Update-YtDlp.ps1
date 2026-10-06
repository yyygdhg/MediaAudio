param([switch]$NoPause)
$ErrorActionPreference='Stop'
$code=0
try {
    . (Join-Path $PSScriptRoot 'MediaAudio.Core.ps1')
    . (Join-Path $PSScriptRoot 'MediaAudio.Update.ps1')
    . (Join-Path $PSScriptRoot 'MediaAudio.Dependencies.ps1')
    $root=Split-Path $PSScriptRoot -Parent
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'logs'))
    Ensure-Dependencies $root
    $status=Update-YtDlp $root -Force
    if (-not $status.Success) { $code=1 }
}
catch { Write-Host "Update error: $($_.Exception.Message)" -ForegroundColor Red; $code=1 }
finally { if (-not $NoPause) { Write-Host 'Press Enter to close'; [void](Read-Host '>') } }
exit $code
