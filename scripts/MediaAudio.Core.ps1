# Windows PowerShell 5.1. Save this script as UTF-8 with BOM.
Set-StrictMode -Version 2.0
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:LogEnabled = $false
$script:LogPath = $null

function Get-Property($Object, [string]$Name, $Default = $null) {
    if ($Object -is [Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) {
        return $Object.$Name
    }
    return $Default
}

function Get-DefaultConfigText {
    return @'
[General]
output_directory=%USERPROFILE%\Desktop
auto_update_ytdlp=true
download_playlist=false
cookies_from_browser=
cookies_file=
open_folder_when_finished=false
pause_after_finished=true
write_log=true

[Output]
output_mode=alac
'@
}

function Read-Configuration([string]$Path, [string]$Root) {
    if (-not (Test-Path -LiteralPath $Path)) {
        [IO.File]::WriteAllText($Path, (Get-DefaultConfigText), $script:Utf8)
        Write-Host 'config.ini missing: restored default configuration.'
    }
    $values = @{}
    $section = ''
    foreach ($raw in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[([^\]]+)\]$') { $section = $matches[1]; continue }
        if ($line -notmatch '^([^=]+)=(.*)$') { throw 'Invalid config line: expected key=value or [section].' }
        $values[($section + '.' + $matches[1].Trim()).ToLowerInvariant()] = $matches[2].Trim()
    }
    $defaults = @{
        'general.output_directory' = '%USERPROFILE%\Desktop'
        'general.auto_update_ytdlp' = 'true'; 'general.download_playlist' = 'false'
        'general.cookies_from_browser' = ''; 'general.cookies_file' = ''; 'general.open_folder_when_finished' = 'false'
        'general.pause_after_finished' = 'true'; 'general.write_log' = 'true'
        'output.output_mode' = 'alac'
    }
    foreach ($key in $defaults.Keys) {
        if (-not $values.ContainsKey($key)) { $values[$key] = $defaults[$key] }
    }
    $config = @{}
    foreach ($name in @('auto_update_ytdlp','download_playlist','open_folder_when_finished','pause_after_finished','write_log')) {
        $value = $values['general.' + $name].ToLowerInvariant()
        if ($value -notin @('true','false')) { throw "Config $name must be true or false." }
        $config[$name] = ($value -eq 'true')
    }
    $mode = $values['output.output_mode'].ToLowerInvariant()
    if ($mode -notin @('original','alac')) { throw 'output_mode must be original or alac.' }
    $config.output_mode = $mode
    $directory = [Environment]::ExpandEnvironmentVariables($values['general.output_directory'])
    if (-not $directory -or $directory -match '%[^%]+%') { throw 'Invalid output_directory environment variable.' }
    if (-not [IO.Path]::IsPathRooted($directory)) { $directory = Join-Path $Root $directory }
    $config.output_directory = [IO.Path]::GetFullPath($directory)
    $config.cookies_from_browser = $values['general.cookies_from_browser']
    $config.cookies_file = ''
    if ($values['general.cookies_file']) {
        $cookiePath = [Environment]::ExpandEnvironmentVariables($values['general.cookies_file'])
        if ($cookiePath -match '%[^%]+%') { throw 'Invalid cookies_file environment variable.' }
        if (-not [IO.Path]::IsPathRooted($cookiePath)) { $cookiePath = Join-Path $Root $cookiePath }
        $config.cookies_file = [IO.Path]::GetFullPath($cookiePath)
    }
    return $config
}

function Protect-LogText([string]$Text) {
    # Mentioning a cookie option or a login requirement is not itself a secret.
    # Redact actual credential/header values, retaining actionable error messages.
    $Text = [regex]::Replace($Text, '(?im)^\s*(?:\[debug\]\s*)?(?:cookie|set-cookie|authorization|proxy-authorization)\s*:[^\r\n]*', '[Sensitive header omitted]')
    $Text = [regex]::Replace($Text, '(?i)"(cookie|cookies|authorization|password|username|email|access_token|refresh_token)"\s*:\s*"[^"\r\n]*"', '"$1":"[redacted]"')
    $Text = [regex]::Replace($Text, '(?i)\b(password|passwd|username|email|access[_-]?token|refresh[_-]?token|api[_-]?key)\s*[:=]\s*(?:"[^"\r\n]*"|''[^''\r\n]*''|[^\s,;]+)', '$1=[redacted]')
    $Text = [regex]::Replace($Text, '(?i)\blogged\s+in\s+as\s+\S+', 'logged in as [redacted]')
    # Keep normal video identifiers, remove signed URLs, credentials and other query values.
    $Text = [regex]::Replace($Text, '(?i)(https?://)[^/\s@]+@', '$1[redacted]@')
    $Text = [regex]::Replace($Text, '([?#&])([^=&#\s]+)=([^&#\s]*)', {
        param($match)
        if ($match.Groups[2].Value -in @('v','p','bvid','list')) { return $match.Value }
        return $match.Groups[1].Value + $match.Groups[2].Value + '=[redacted]'
    })
    $Text = [regex]::Replace($Text, '(?i)[\w.+-]+@[\w.-]+\.[a-z]{2,}', '[redacted-email]')
    return ($Text -replace '[\r\n]+', ' ')
}

function Write-Log([string]$Message) {
    if ($script:LogEnabled) {
        $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + (Protect-LogText $Message)
        [IO.File]::AppendAllText($script:LogPath, $line + [Environment]::NewLine, $script:Utf8)
    }
}

function ConvertTo-NativeArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting. Never invoke a shell for URLs/paths.
    return '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [switch]$ShowOutput, [int]$TimeoutSeconds = 0)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Exe
    $start.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $script:Utf8
    $start.StandardErrorEncoding = $script:Utf8
    $start.EnvironmentVariables['PYTHONUTF8'] = '1'
    $start.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $outLines = New-Object 'Collections.Generic.List[string]'
    $errLines = New-Object 'Collections.Generic.List[string]'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $started = $false
    try {
        [void]$process.Start()
        $started = $true
        $outTask = $process.StandardOutput.ReadLineAsync()
        $errTask = $process.StandardError.ReadLineAsync()
        while ($null -ne $outTask -or $null -ne $errTask) {
            if ($TimeoutSeconds -gt 0 -and $timer.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                if (-not $process.HasExited) { $process.Kill() }
                throw "$(Split-Path $Exe -Leaf) exceeded $TimeoutSeconds seconds."
            }
            $readAny = $false
            if ($null -ne $outTask -and $outTask.IsCompleted) {
                $line = $outTask.GetAwaiter().GetResult()
                if ($null -eq $line) { $outTask = $null }
                else {
                    $outLines.Add($line)
                    if ($ShowOutput) { Write-Host $line }
                    $outTask = $process.StandardOutput.ReadLineAsync()
                }
                $readAny = $true
            }
            if ($null -ne $errTask -and $errTask.IsCompleted) {
                $line = $errTask.GetAwaiter().GetResult()
                if ($null -eq $line) { $errTask = $null }
                else {
                    $errLines.Add($line)
                    if ($ShowOutput) { Write-Host $line }
                    $errTask = $process.StandardError.ReadLineAsync()
                }
                $readAny = $true
            }
            if (-not $readAny) { Start-Sleep -Milliseconds 15 }
        }
        $process.WaitForExit()
        return [pscustomobject]@{ExitCode=$process.ExitCode; StdOut=$outLines.ToArray(); StdErr=$errLines.ToArray()}
    }
    finally {
        if ($started -and -not $process.HasExited) { $process.Kill() }
        $process.Dispose()
    }
}

function Assert-NativeSuccess($Result, [string]$Action) {
    if ($Result.ExitCode -ne 0) {
        $diagnostic = (@($Result.StdErr | Where-Object { $_ -notmatch '^\s*\[debug\]' } | Select-Object -Last 5) -join "`n")
        throw "$Action failed (exit $($Result.ExitCode)). $(Protect-LogText $diagnostic)"
    }
}

function Show-RecoveryAdvice([string]$Message, $Config) {
    if ($Message -match '(?i)(DPAPI|decrypt.*cookie|cookie.*decrypt)') {
        Write-Host ''
        Write-Host '浏览器 Cookie 解密失败。请从自己的 Chrome 导出 YouTube 的 Netscape Cookie 文件，在 config.ini 中填写 cookies_file=本地文件路径。' -ForegroundColor Yellow
        Write-Host 'Cookie 文件方式优先于 cookies_from_browser；无需关闭浏览器加密保护。请勿把 Cookie 内容上传或粘贴到聊天中。'
        return
    }
    if ($Message -match '(?i)(confirm.*not a bot|LOGIN_REQUIRED|login required|sign in|age.restricted|private video)') {
        Write-Host ''
        Write-Host '网站要求登录 / 人机验证，当前请求没有获得访问音轨的权限。' -ForegroundColor Yellow
        if (-not $Config -or (-not $Config.cookies_from_browser -and -not (Get-Property $Config 'cookies_file' ''))) {
            Write-Host '浏览器 Cookie 当前关闭；工具没有擅自读取它们。'
            Write-Host '如需登录访问：先在自己的 Edge/Chrome 中登录并完成网站要求的验证，再设置 cookies_from_browser=edge 或 chrome，或 cookies_file=本地 Netscape Cookie 文件路径。'
        }
        else {
            Write-Host '已启用指定的 Cookie 来源。请确认对应浏览器已登录并能播放此视频；账号权限、Cookie 过期或网站验证仍可能阻止访问。'
        }
        Write-Host '更新 yt-dlp 能修复解析问题，但不能保证解除网站的登录或验证要求。'
    }
}

function Assert-CookieFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Configured cookies_file was not found. Export a Netscape Cookie file locally or clear cookies_file.'
    }
    $reader = [IO.File]::OpenText($Path)
    try { $header = $reader.ReadLine() } finally { $reader.Dispose() }
    if ($header -notin @('# HTTP Cookie File','# Netscape HTTP Cookie File')) {
        throw 'cookies_file must use Netscape format; its first line must be # Netscape HTTP Cookie File or # HTTP Cookie File.'
    }
}

function Get-YtArguments([string]$Root, $Config, [switch]$Anonymous) {
    $arguments = @('--ignore-config','--no-plugin-dirs','--encoding','utf-8',
        '--ffmpeg-location',(Join-Path $Root 'bin'),'--cache-dir',(Join-Path $Root 'logs\cache'),
        '--socket-timeout','25','--retries','3','--fragment-retries','3',
        '--no-write-comments','--js-runtimes',('node:' + (Join-Path $Root 'bin\node.exe')))
    if ($Anonymous) { $arguments += @('--no-cookies','--no-cookies-from-browser') }
    elseif (Get-Property $Config 'cookies_file' '') {
        Assert-CookieFile $Config.cookies_file
        $arguments += @('--no-cookies-from-browser','--cookies',$Config.cookies_file)
    }
    elseif ($Config.cookies_from_browser) { $arguments += @('--cookies-from-browser',$Config.cookies_from_browser) }
    else { $arguments += @('--no-cookies','--no-cookies-from-browser') }
    return $arguments
}

function Test-AuthenticationRequired([string]$Message) {
    return ($Message -match '(?i)(confirm.*not a bot|LOGIN_REQUIRED|login required|please log in|sign in|age[ ._-]?restricted|private video|authentication.*required|cookies?.*required)')
}

function Get-MetadataWithAuthentication([string]$Root, $Config, [string[]]$RequestArguments) {
    $common = @(Get-YtArguments $Root $Config -Anonymous)
    Write-Host 'Trying without cookies...'
    Write-Log 'Metadata request: anonymous; no browser/local Cookie access.'
    $result = Invoke-Native (Join-Path $Root 'bin\yt-dlp.exe') ($common + $RequestArguments) -TimeoutSeconds 600
    $usedCookies = $false
    $diagnostic = $result.StdErr -join ' '
    if ($result.ExitCode -ne 0 -and (Test-AuthenticationRequired $diagnostic) -and
        ($Config.cookies_from_browser -or (Get-Property $Config 'cookies_file' ''))) {
        Write-Host 'Website requires authentication; retrying with your configured cookies...' -ForegroundColor Yellow
        Write-Log 'Website requested authentication; retrying explicitly configured Cookie source.'
        $common = @(Get-YtArguments $Root $Config)
        $result = Invoke-Native (Join-Path $Root 'bin\yt-dlp.exe') ($common + $RequestArguments) -TimeoutSeconds 600
        $usedCookies = $true
    }
    return [pscustomobject]@{Result=$result;Arguments=$common;CookiesUsed=$usedCookies}
}

function Get-MediaEntries($Info) {
    if ($null -ne $Info -and $null -ne $Info.PSObject.Properties['entries']) {
        foreach ($entry in $Info.entries) { if ($null -ne $entry) { Get-MediaEntries $entry } }
    }
    elseif ($null -ne $Info) { $Info }
}

function Get-AudioProbe([string]$Root, [string]$Path) {
    $result = Invoke-Native (Join-Path $Root 'bin\ffprobe.exe') @('-v','error','-show_entries',
        'stream=codec_type,codec_name,sample_rate,channels,channel_layout,bit_rate:format=format_name,duration,size,bit_rate','-of','json',$Path)
    Assert-NativeSuccess $result 'ffprobe'
    $info = ($result.StdOut -join "`n") | ConvertFrom-Json
    $audio = @($info.streams | Where-Object { $_.codec_type -eq 'audio' })
    if ($audio.Count -lt 1) { throw 'No decodable audio stream found.' }
    $stream = $audio[0]
    if ([int](Get-Property $stream 'sample_rate' 0) -le 0 -or [int](Get-Property $stream 'channels' 0) -le 0) {
        throw 'ffprobe did not report a valid sample rate and channel count.'
    }
    return [pscustomobject]@{Stream=$stream; Format=$info.format; Streams=$info.streams}
}

function Assert-AudioParameters($Source, $Final, [string]$Mode) {
    $expectedCodec = $Source.Stream.codec_name
    if ($Mode -eq 'alac') { $expectedCodec = 'alac' }
    if ($Final.Stream.codec_name -ne $expectedCodec) { throw "Unexpected final codec: $($Final.Stream.codec_name)" }
    if ($Source.Stream.sample_rate -ne $Final.Stream.sample_rate -or $Source.Stream.channels -ne $Final.Stream.channels) {
        throw 'Output sample rate or channel count differs from the source. Source is retained.'
    }
    $sourceDuration = [double](Get-Property $Source.Format 'duration' 0)
    $finalDuration = [double](Get-Property $Final.Format 'duration' 0)
    if ($finalDuration -le 0 -or ($sourceDuration -gt 0 -and [Math]::Abs($sourceDuration-$finalDuration) -gt 0.25)) {
        throw 'Output duration is invalid or does not match the source. Source is retained.'
    }
}

function Test-FullDecode([string]$Root, [string]$Path) {
    Write-Host 'Verifying full decode...'
    $result = Invoke-Native (Join-Path $Root 'bin\ffmpeg.exe') @('-hide_banner','-nostdin','-v','error',
        '-xerror','-err_detect','explode','-i',$Path,'-map','0:a:0','-f','null','-')
    Assert-NativeSuccess $result 'Full decode check'
    if (@($result.StdErr).Count -gt 0) { throw "Decode errors: $(Protect-LogText ($result.StdErr -join ' '))" }
}

function Get-SafeTitle([string]$Title, [string]$Directory) {
    $title = ($Title -replace '[<>:"/\\|?*\x00-\x1f]', '_').Trim().TrimEnd('.', ' ')
    if (-not $title) { $title = 'Untitled' }
    if ($title -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { $title = '_' + $title }
    $maxLength = [Math]::Min(180, 235 - $Directory.Length - 16)
    if ($maxLength -lt 12) { throw 'Output directory path is too long; choose a shorter path.' }
    if ($title.Length -gt $maxLength) {
        $title = $title.Substring(0,$maxLength)
        if ([char]::IsHighSurrogate($title[$title.Length-1])) { $title = $title.Substring(0,$title.Length-1) }
        $title = $title.TrimEnd('.', ' ')
    }
    return $title
}

function Move-ToUniqueOutput([string]$Source, [string]$Directory, [string]$Title, [string]$Extension) {
    $safeTitle = Get-SafeTitle $Title $Directory
    for ($index = 0; $index -lt 10000; $index++) {
        $suffix = ''; if ($index -gt 0) { $suffix = " ($index)" }
        $target = Join-Path $Directory ($safeTitle + $suffix + $Extension)
        if (Test-Path -LiteralPath $target) { continue }
        try { [IO.File]::Move($Source,$target); return $target }
        catch [IO.IOException] { if (Test-Path -LiteralPath $target) { continue }; throw }
    }
    throw 'Too many files have the same title.'
}

function Get-AudioExtension([string]$Codec) {
    switch ($Codec) {
        'opus' { return '.webm' }; 'aac' { return '.m4a' }; 'alac' { return '.m4a' }
        'mp3' { return '.mp3' }; 'flac' { return '.flac' }; 'vorbis' { return '.ogg' }
        default { return '.mka' }
    }
}

function Remove-OwnStage([string]$Stage, [string]$WorkRoot) {
    $fullStage = [IO.Path]::GetFullPath($Stage)
    $fullRoot = [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\') + '\'
    if (-not $fullStage.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $fullStage -Leaf) -notmatch '^job-[0-9a-f]{32}$') { throw 'Refusing unsafe temporary cleanup.' }
    if ((Get-Item -LiteralPath $fullStage).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Refusing to delete a redirected temporary directory.'
    }
    Remove-Item -LiteralPath $fullStage -Recurse -Force
}

function Complete-Audio {
    param([string]$Root, $Config, [string]$SourcePath, [string]$Stage, [string]$Title)
    $source = Get-AudioProbe $Root $SourcePath
    Write-Host "Source codec: $($source.Stream.codec_name)"
    Write-Host "Source sample rate: $($source.Stream.sample_rate) Hz"
    Write-Host "Source channels: $($source.Stream.channels)"
    Write-Log "Source codec: $($source.Stream.codec_name); sample rate: $($source.Stream.sample_rate); channels: $($source.Stream.channels)"
    $candidate = $SourcePath
    if ($Config.output_mode -eq 'alac') {
        $candidate = Join-Path $Stage 'final.m4a'
        Write-Host 'Encoding ALAC (no audio filters, original sample rate/channels)...'
        $result = Invoke-Native (Join-Path $Root 'bin\ffmpeg.exe') @('-hide_banner','-nostdin','-n',
            '-i',$SourcePath,'-map','0:a:0','-vn','-c:a','alac',$candidate) -ShowOutput
        Assert-NativeSuccess $result 'ALAC conversion'
    }
    elseif (@($source.Streams | Where-Object { $_.codec_type -ne 'audio' }).Count -gt 0 -or @($source.Streams).Count -gt 1) {
        $candidate = Join-Path $Stage ('audio' + (Get-AudioExtension $source.Stream.codec_name))
        Write-Host 'Separating original audio with stream copy (no re-encoding)...'
        $result = Invoke-Native (Join-Path $Root 'bin\ffmpeg.exe') @('-hide_banner','-nostdin','-n',
            '-i',$SourcePath,'-map','0:a:0','-vn','-c:a','copy',$candidate) -ShowOutput
        Assert-NativeSuccess $result 'Audio stream copy'
    }
    $final = Get-AudioProbe $Root $candidate
    Assert-AudioParameters $source $final $Config.output_mode
    Test-FullDecode $Root $candidate
    $saved = Move-ToUniqueOutput $candidate $Config.output_directory $Title ([IO.Path]::GetExtension($candidate))
    # The source is cleaned up by the caller only AFTER verified output is promoted.
    Write-Host ''
    Write-Host 'SUCCESS - ffprobe and full decode passed.' -ForegroundColor Green
    Write-Host "Final codec: $($final.Stream.codec_name)"
    Write-Host "Container: $($final.Format.format_name)"
    Write-Host "Sample rate: $($final.Stream.sample_rate) Hz"
    Write-Host "Channels: $($final.Stream.channels)"
    Write-Host "Duration: $($final.Format.duration) seconds"
    Write-Host "Bit rate: $(Get-Property $final.Stream 'bit_rate' 'not reported') bps (audio); $(Get-Property $final.Format 'bit_rate' 'not reported') bps (container average)"
    Write-Host "File size: $($final.Format.size) bytes"
    Write-Host "Saved to: $saved"
    Write-Log "Final codec: $($final.Stream.codec_name); container: $($final.Format.format_name); sample rate: $($final.Stream.sample_rate); channels: $($final.Stream.channels); duration: $($final.Format.duration); bit_rate: $(Get-Property $final.Format 'bit_rate' 'unknown'); size: $($final.Format.size); full decode: passed; saved to: $saved"
    return [pscustomobject]@{Path=$saved;Source=$source;Final=$final}
}
