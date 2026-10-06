# Uses only the official GitHub release page/assets when the API updater is limited.
# Requires MediaAudio.Core.ps1. Windows PowerShell 5.1, UTF-8 BOM.
function Get-OfficialYtRelease([string]$Repository) {
    if ($Repository -notin @('yt-dlp/yt-dlp','yt-dlp/yt-dlp-nightly-builds')) { throw 'Unsupported update source.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -UseBasicParsing -Method Head -Uri ('https://github.com/' + $Repository + '/releases/latest') -TimeoutSec 20
    $uri = Get-Property $response.BaseResponse 'ResponseUri'
    if ($null -eq $uri) {
        $request = Get-Property $response.BaseResponse 'RequestMessage'
        $uri = Get-Property $request 'RequestUri'
    }
    if ($null -eq $uri -or $uri.Host -ne 'github.com') { throw 'Could not verify official release redirect.' }
    $pattern = '^/' + [regex]::Escape($Repository) + '/releases/tag/([0-9A-Za-z._-]+)$'
    if ($uri.AbsolutePath -notmatch $pattern) { throw 'Unexpected official release URL.' }
    return [pscustomobject]@{Tag=$matches[1];DownloadBase=('https://github.com/' + $Repository + '/releases/download/' + $matches[1] + '/')}
}

function Get-YtDigest($ChecksumText) {
    if ($ChecksumText -is [byte[]]) { $ChecksumText = [Text.Encoding]::UTF8.GetString($ChecksumText) }
    else { $ChecksumText = [string]$ChecksumText }
    $lines = @($ChecksumText -split '\r?\n' | Where-Object { $_ -match '^[0-9a-fA-F]{64}\s+\*?yt-dlp\.exe$' })
    if ($lines.Count -ne 1) { throw 'Official SHA256 file does not contain exactly one yt-dlp.exe entry.' }
    return ($lines[0] -split '\s+')[0].ToUpperInvariant()
}

function Assert-YtDigest([string]$Path, [string]$Expected) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) { throw 'Official yt-dlp SHA256 verification failed; installed executable retained.' }
}

function Install-OfficialYtFallback([string]$Root, [string]$Repository) {
    $priorProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    $pendingDirectory = $null
    try {
        $release = Get-OfficialYtRelease $Repository
        $checksum = Invoke-WebRequest -UseBasicParsing -Uri ($release.DownloadBase + 'SHA2-256SUMS') -TimeoutSec 30
        $expected = Get-YtDigest $checksum.Content
        $exe = Join-Path $Root 'bin\yt-dlp.exe'
        $installed = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
        if ($installed -eq $expected) {
            Write-Host "Official release verified: $($release.Tag) is already installed."
            return $release.Tag
        }
        $updateRoot = Join-Path $Root 'logs\updates'
        [void][IO.Directory]::CreateDirectory($updateRoot)
        if ((Get-Item -LiteralPath $updateRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Update directory must not be redirected.' }
        $pendingDirectory = Join-Path $updateRoot ('pending-' + [Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($pendingDirectory)
        $pendingExe = Join-Path $pendingDirectory 'yt-dlp.exe'
        Write-Host "Downloading official yt-dlp $($release.Tag)..."
        Invoke-WebRequest -UseBasicParsing -Uri ($release.DownloadBase + 'yt-dlp.exe') -OutFile $pendingExe -TimeoutSec 120
        Assert-YtDigest $pendingExe $expected
        $version = Invoke-Native $pendingExe @('--ignore-config','--no-plugin-dirs','--version') -TimeoutSeconds 30
        Assert-NativeSuccess $version 'Updated yt-dlp version check'
        if (($version.StdOut -join '').Trim() -ne $release.Tag) { throw 'Downloaded executable version does not match the official release tag.' }
        $backup = Join-Path $updateRoot ('yt-dlp-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N') + '.exe')
        # Same-volume atomic swap; only a verified executable can replace the current one.
        [IO.File]::Replace($pendingExe,$exe,$backup,$true)
        Write-Host "Updated to $($release.Tag); previous executable backed up."
        return $release.Tag
    }
    finally {
        $ProgressPreference = $priorProgressPreference
        if ($pendingDirectory -and (Test-Path -LiteralPath $pendingDirectory)) {
            $expectedRoot = [IO.Path]::GetFullPath((Join-Path $Root 'logs\updates')).TrimEnd('\') + '\'
            $fullPending = [IO.Path]::GetFullPath($pendingDirectory)
            if ($fullPending.StartsWith($expectedRoot,[StringComparison]::OrdinalIgnoreCase) -and
                (Split-Path $fullPending -Leaf) -match '^pending-[0-9a-f]{32}$' -and
                -not ((Get-Item -LiteralPath $fullPending).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $fullPending -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Update-YtDlp([string]$Root, [switch]$Force) {
    $statePath = Join-Path $Root 'logs\update-state.json'
    $exe = Join-Path $Root 'bin\yt-dlp.exe'
    $installedVersion = Invoke-Native $exe @('--ignore-config','--version') -TimeoutSeconds 30
    Assert-NativeSuccess $installedVersion 'Installed yt-dlp version check'
    $versionString = ($installedVersion.StdOut -join '').Trim()
    if (-not $Force -and (Test-Path -LiteralPath $statePath)) {
        try {
            $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
            $age = [DateTime]::UtcNow - [DateTime]::Parse($state.CheckedUtc).ToUniversalTime()
            $cooldown = 1; if ($state.Success) { $cooldown = 24 }
            if ($state.InstalledVersion -eq $versionString -and $age.TotalHours -ge 0 -and $age.TotalHours -lt $cooldown) {
                Write-Host 'Recent update check reused; avoiding repeated update requests.'
                Write-Log "Update check reused; installed version: $versionString"
                return [pscustomobject]@{Success=[bool]$state.Success;Version=$versionString;Cached=$true}
            }
        }
        catch { Write-Log 'Invalid update cache ignored.' }
    }
    Write-Host 'Checking yt-dlp updates (failure will not stop downloads)...'
    $success = $false
    try {
        $update = Invoke-Native $exe @('--ignore-config','--no-plugin-dirs','--encoding','utf-8','--socket-timeout','15','-U') -TimeoutSeconds 45
        if ($update.ExitCode -eq 0) {
            foreach ($line in $update.StdOut) { Write-Host $line }
            $success = $true
        }
        else { Write-Log "Native updater failed (exit $($update.ExitCode)): $(Protect-LogText ($update.StdErr -join "`n"))" }
    }
    catch { Write-Log "Native updater unavailable: $($_.Exception.Message)" }
    if (-not $success) {
        Write-Host 'Update API unavailable; checking official release assets instead...'
        try {
            $repository = 'yt-dlp/yt-dlp'
            if ($versionString -match '^\d{4}\.\d{2}\.\d{2}\.\d+$') { $repository = 'yt-dlp/yt-dlp-nightly-builds' }
            $versionString = Install-OfficialYtFallback $Root $repository
            $success = $true
            Write-Log "Official release fallback verified: $versionString"
        }
        catch {
            Write-Host "Update unavailable; continuing with installed version. $(Protect-LogText $_.Exception.Message)" -ForegroundColor Yellow
            Write-Log "Official update fallback unavailable: $($_.Exception.Message); continuing."
        }
    }
    $observedVersion = Invoke-Native $exe @('--ignore-config','--version') -TimeoutSeconds 30
    Assert-NativeSuccess $observedVersion 'yt-dlp post-update version check'
    [IO.File]::WriteAllText($statePath,([pscustomobject]@{CheckedUtc=[DateTime]::UtcNow.ToString('o');Success=$success;InstalledVersion=($observedVersion.StdOut -join '').Trim()} | ConvertTo-Json),$script:Utf8)
    return [pscustomobject]@{Success=$success;Version=($observedVersion.StdOut -join '').Trim();Cached=$false}
}
