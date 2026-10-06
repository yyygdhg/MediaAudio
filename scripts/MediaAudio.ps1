param([string]$Url = '', [string]$ConfigPath = '', [switch]$NoPause)
$ErrorActionPreference = 'Stop'
$exitCode = 1
$pauseAtEnd = $true
$runLock = $null
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
    . (Join-Path $PSScriptRoot 'MediaAudio.Core.ps1')
    . (Join-Path $PSScriptRoot 'MediaAudio.Update.ps1')
    . (Join-Path $PSScriptRoot 'MediaAudio.Dependencies.ps1')
    $root = Split-Path $PSScriptRoot -Parent
    if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'config.ini' }
    Write-Host '----------------------------------------'
    Write-Host 'Universal Media Audio Tool'
    Write-Host '----------------------------------------'
    $config = Read-Configuration $ConfigPath $root
    $pauseAtEnd = $config.pause_after_finished
    $logDirectory = Join-Path $root 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    try {
        $runLock = [IO.File]::Open((Join-Path $logDirectory 'run.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    }
    catch { throw 'Another instance is running. Close it before starting this tool again.' }
    $script:LogEnabled = $config.write_log
    $script:LogPath = Join-Path $logDirectory 'latest.log'
    if ($script:LogEnabled) { [IO.File]::WriteAllText($script:LogPath,'',$script:Utf8) }
    Write-Log "Started. output_mode=$($config.output_mode)"
    Ensure-Dependencies $root
    foreach ($name in @('yt-dlp.exe','ffmpeg.exe','ffprobe.exe','node.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root ('bin\' + $name)))) { throw "Missing bin\$name. Restore the portable dependency." }
    }
    $yt = Join-Path $root 'bin\yt-dlp.exe'
    if ($config.auto_update_ytdlp) {
        try { $updateStatus = Update-YtDlp $root }
        catch {
            Write-Host "Update unavailable; continuing with installed version. $(Protect-LogText $_.Exception.Message)" -ForegroundColor Yellow
            Write-Log "Update check failed; continued: $($_.Exception.Message)"
        }
    }
    $version = Invoke-Native $yt @('--ignore-config','--version') -TimeoutSeconds 30
    Assert-NativeSuccess $version 'yt-dlp version check'
    Write-Host "yt-dlp: $($version.StdOut -join '')"
    Write-Log "yt-dlp version: $($version.StdOut -join '')"
    if (-not $Url) {
        Write-Host '请输入视频链接 / Video URL:'
        $Url = Read-Host '>'
    }
    $Url = $Url.Trim().Trim('"')
    $parsedUrl = $null
    if (-not [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$parsedUrl) -or $parsedUrl.Scheme -notin @('http','https')) {
        throw '请输入完整的 http:// 或 https:// 视频链接 / Invalid video URL.'
    }
    Write-Log "Input URL: $Url"
    [void][IO.Directory]::CreateDirectory($config.output_directory)
    $workRoot = Join-Path $config.output_directory '.MediaAudio-work'
    [void][IO.Directory]::CreateDirectory($workRoot)
    if ((Get-Item -LiteralPath $workRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Temporary work directory must not be a junction or symbolic link.'
    }
    $selection = @('--no-playlist','--playlist-items','1')
    if ($config.download_playlist) { $selection = @('--yes-playlist') }
    Write-Host 'Reading title and available audio formats...'
    $extraction = Get-MetadataWithAuthentication $root $config ($selection + @('--format','bestaudio/best','--dump-single-json','--no-clean-info-json','--skip-download',$Url))
    $metadata = $extraction.Result
    $common = @($extraction.Arguments)
    Assert-NativeSuccess $metadata 'Video extraction'
    $info = ($metadata.StdOut -join "`n") | ConvertFrom-Json
    $entries = @(Get-MediaEntries $info)
    if (-not $config.download_playlist -and $entries.Count -gt 1) { $entries = @($entries[0]) }
    if ($entries.Count -eq 0) { throw 'No media entries were found.' }
    $successCount = 0; $failedCount = 0
    foreach ($entry in $entries) {
        $infoPath = $null
        $stage = Join-Path $workRoot ('job-' + [Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($stage)
        try {
            $title = [string](Get-Property $entry 'title' (Get-Property $entry 'id' 'Untitled'))
            $formatId = [string](Get-Property $entry 'format_id' '')
            if (-not $formatId) { throw 'yt-dlp did not select an audio format.' }
            Write-Host ''
            Write-Host "Title: $title"
            Write-Host "Site: $(Get-Property $entry 'extractor' 'unknown')"
            Write-Host "Selected format ID: $formatId"
            Write-Host "Source codec: $(Get-Property $entry 'acodec' 'unknown until download')"
            Write-Host "Source sample rate: $(Get-Property $entry 'asr' 'unknown until download')"
            Write-Log "Title: $title; site: $(Get-Property $entry 'extractor' 'unknown'); format ID: $formatId"
            $infoPath = Join-Path $stage 'source-info.json'
            [IO.File]::WriteAllText($infoPath,($entry | ConvertTo-Json -Depth 100 -Compress),$script:Utf8)
            $pathRecord = Join-Path $stage 'source-path.txt'
            Write-Host 'Downloading...'
            $download = Invoke-Native $yt ($common + @('--no-playlist','--format',$formatId,
                '--fixup','never','--no-overwrites','--newline','--progress',
                '--progress-template','download:%(progress._percent_str)s | %(progress._speed_str)s | ETA %(progress._eta_str)s',
                '--output',(Join-Path ($stage.Replace('%','%%')) 'source.%(ext)s'),
                '--print-to-file','after_move:filepath',$pathRecord,'--load-info-json',$infoPath)) -ShowOutput
            Assert-NativeSuccess $download 'Audio download'
            if (-not (Test-Path -LiteralPath $pathRecord)) { throw 'Download did not report a source file.' }
            $sourcePath = [IO.File]::ReadAllLines($pathRecord,$script:Utf8) | Select-Object -Last 1
            $sourcePath = [IO.Path]::GetFullPath($sourcePath)
            if (-not $sourcePath.StartsWith($stage + '\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $sourcePath)) {
                throw 'Downloaded file is missing or outside its task directory.'
            }
            $completed = Complete-Audio $root $config $sourcePath $stage $title
            $successCount++
            try { Remove-OwnStage $stage $workRoot }
            catch { Write-Host "Output verified; temporary cleanup failed: $stage"; Write-Log "Temporary cleanup failed: $stage" }
        }
        catch {
            $failedCount++
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Downloaded source / partial files retained at: $stage"
            Write-Log "ERROR: $($_.Exception.Message); files retained at: $stage"
            Show-RecoveryAdvice $_.Exception.Message $config
        }
        finally {
            # Metadata can include private request headers with configured browser cookies.
            # Keep downloaded/partial audio on failure, but never retain that metadata.
            if ($infoPath -and (Test-Path -LiteralPath $infoPath)) {
                Remove-Item -LiteralPath $infoPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Write-Host "Finished: $successCount successful, $failedCount failed."
    if ($config.open_folder_when_finished -and $successCount -gt 0) {
        Start-Process -FilePath explorer.exe -ArgumentList ('"' + $config.output_directory + '"')
    }
    if ($failedCount -eq 0 -and $successCount -gt 0) { $exitCode = 0 }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log "ERROR: $($_.Exception.Message)" }
    if (Get-Command Show-RecoveryAdvice -ErrorAction SilentlyContinue) {
        $activeConfig = $null; if (Get-Variable config -ErrorAction SilentlyContinue) { $activeConfig = $config }
        Show-RecoveryAdvice $_.Exception.Message $activeConfig
    }
}
finally {
    if ($null -ne $runLock) { $runLock.Dispose() }
    if ($pauseAtEnd -and -not $NoPause) {
        Write-Host '按 Enter 关闭 / Press Enter to close'
        try { [void](Read-Host '>') } catch { }
    }
}
exit $exitCode
