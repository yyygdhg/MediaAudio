param([switch]$NoPause)
$ErrorActionPreference='Stop'
$code=0
try {
    . (Join-Path $PSScriptRoot 'MediaAudio.Core.ps1')
    . (Join-Path $PSScriptRoot 'MediaAudio.Dependencies.ps1')
    Ensure-Dependencies (Split-Path $PSScriptRoot -Parent)
    Write-Host 'Dependencies are ready / 依赖已就绪。'
}
catch { Write-Host "Setup error: $($_.Exception.Message)" -ForegroundColor Red; $code=1 }
finally { if (-not $NoPause) { Write-Host 'Press Enter to close'; [void](Read-Host '>') } }
exit $code
