param([switch]$Network, [string]$YouTubeUrl = 'https://www.youtube.com/watch?v=7EjKc52VGvY',
    [string]$BilibiliUrl = 'https://www.bilibili.com/video/BV1xx411c7mD')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'MediaAudio.Core.ps1')
$root = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $root ('logs\tests-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
[void][IO.Directory]::CreateDirectory($testRoot)
$results = New-Object 'Collections.Generic.List[object]'
function Record([string]$Name, [scriptblock]$Test) {
    try { & $Test; $results.Add([pscustomobject]@{Test=$Name;Passed=$true;Detail='Passed'}) }
    catch { $results.Add([pscustomobject]@{Test=$Name;Passed=$false;Detail=$_.Exception.Message}); Write-Host "FAIL $Name : $($_.Exception.Message)" }
}
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Test-Config([string]$Mode, [string]$Directory) {
    $path = Join-Path $testRoot ($Mode + '-' + [Guid]::NewGuid().ToString('N') + '.ini')
    $text = (Get-DefaultConfigText).Replace('output_mode=alac',"output_mode=$Mode").Replace(
        'output_directory=%USERPROFILE%\Desktop',"output_directory=$Directory").Replace('auto_update_ytdlp=true','auto_update_ytdlp=false').Replace('pause_after_finished=true','pause_after_finished=false')
    [IO.File]::WriteAllText($path,$text,$script:Utf8)
    return $path
}
Record 'Dependency executables' {
    foreach ($name in @('yt-dlp.exe','ffmpeg.exe','ffprobe.exe','node.exe')) {
        $arg = '-version'; if ($name -in @('yt-dlp.exe','node.exe')) { $arg = '--version' }
        Assert-NativeSuccess (Invoke-Native (Join-Path $root "bin\$name") @($arg) -TimeoutSeconds 30) $name
    }
}
Record 'Restore config after deletion; preserve defaults' {
    $path = Join-Path $testRoot 'config.ini'
    $config = Read-Configuration $path $root
    Assert ($config.output_mode -eq 'alac' -and $config.auto_update_ytdlp -and -not $config.download_playlist -and -not $config.cookies_from_browser) 'Incorrect defaults'
    Remove-Item -LiteralPath $path
    $config = Read-Configuration $path $root
    Assert (Test-Path -LiteralPath $path) 'Missing config was not recreated'
    Assert ($config.output_directory -eq (Join-Path $env:USERPROFILE 'Desktop')) 'Default output path incorrect'
}
Record 'Config rejects invalid mode and boolean' {
    $path = Join-Path $testRoot 'invalid.ini'
    [IO.File]::WriteAllText($path,((Get-DefaultConfigText).Replace('output_mode=alac','output_mode=aac')),$script:Utf8)
    $rejected=$false; try { Read-Configuration $path $root | Out-Null } catch { $rejected=$true }
    Assert $rejected 'Accepted AAC configuration'
    [IO.File]::WriteAllText($path,((Get-DefaultConfigText).Replace('write_log=true','write_log=maybe')),$script:Utf8)
    $rejected=$false; try { Read-Configuration $path $root | Out-Null } catch { $rejected=$true }
    Assert $rejected 'Accepted invalid boolean'
}
Record 'Cookie opt-in and log privacy' {
    $config = Read-Configuration (Join-Path $testRoot 'config.ini') $root
    $args = @(Get-YtArguments $root $config)
    Assert ($args -notcontains '--cookies-from-browser' -and $args -contains '--no-cookies-from-browser') 'Default reads browser cookies'
    $config.cookies_from_browser='edge'
    Assert (@(Get-YtArguments $root $config) -contains '--cookies-from-browser') 'Cookie opt-in missing'
    $clean = Protect-LogText 'https://user:secret@example.org/watch?v=abc&token=secret123&key=secret456'
    Assert ($clean -notmatch 'secret|user:') 'URL secrets leaked'
    Assert ((Protect-LogText 'Cookie: session=SECRET') -notmatch 'SECRET') 'Cookie leaked'
}
Record 'Filename safety; Unicode; native argument quoting' {
    Assert ((Get-SafeTitle '中文标题：测试 / ? *' $testRoot) -match '中文标题') 'Chinese filename corrupted'
    Assert ((Get-SafeTitle 'CON' $testRoot) -ne 'CON') 'Reserved filename accepted'
    $result = Invoke-Native (Join-Path $root 'bin\node.exe') @('-e','console.log(JSON.stringify(process.argv.slice(1)))','路径 中文','quote"text','trailing\','& echo NEVER_EXECUTE')
    Assert-NativeSuccess $result 'Argument quoting'
    $actual = ($result.StdOut -join '') | ConvertFrom-Json
    Assert ($actual[0] -eq '路径 中文' -and $actual[1] -eq 'quote"text' -and $actual[2] -eq 'trailing\' -and $actual[3] -eq '& echo NEVER_EXECUTE') 'Native argument corruption'
}
$sources = @{}
Record 'Generate 48000 Hz stereo and 44100 Hz mono fixtures' {
    foreach ($spec in @(@('stereo48',48000,2),@('mono44',44100,1))) {
        $path = Join-Path $testRoot ($spec[0] + '.webm')
        $codec='libopus'; if ($spec[1] -eq 44100) { $path=[IO.Path]::ChangeExtension($path,'.m4a'); $codec='aac' }
        $result = Invoke-Native (Join-Path $root 'bin\ffmpeg.exe') @('-hide_banner','-v','error','-nostdin','-n','-f','lavfi','-i',("sine=frequency=440:sample_rate="+$spec[1]),'-t','2','-ac',([string]$spec[2]),'-c:a',$codec,$path)
        Assert-NativeSuccess $result 'Create test fixture'
        $sources[$spec[0]]=$path
    }
}
foreach ($specName in @('stereo48','mono44')) {
    foreach ($mode in @('original','alac')) {
        Record "$mode conversion $specName; Unicode output; collision safety" {
            $outDir = Join-Path $testRoot '中文 路径 & 测试输出'
            [void][IO.Directory]::CreateDirectory($outDir)
            $config = Read-Configuration (Test-Config $mode $outDir) $root
            $workRoot = Join-Path $outDir '.MediaAudio-work'; [void][IO.Directory]::CreateDirectory($workRoot)
            $stage = Join-Path $workRoot ('job-' + [Guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($stage)
            $source = Join-Path $stage ('source' + [IO.Path]::GetExtension($sources[$specName]))
            Copy-Item -LiteralPath $sources[$specName] -Destination $source
            $hash = (Get-FileHash -LiteralPath $source).Hash
            $title = "中文标题 - $mode - $specName"
            $oldFile = Join-Path $outDir ($title + $(if ($mode -eq 'alac') { '.m4a' } else { [IO.Path]::GetExtension($source) }))
            [IO.File]::WriteAllText($oldFile,'existing file must not change',$script:Utf8)
            $completed = Complete-Audio $root $config $source $stage $title
            Assert ($completed.Path -match '\(1\)') 'Did not protect existing file'
            Assert ([IO.File]::ReadAllText($oldFile) -eq 'existing file must not change') 'Overwrote existing file'
            if ($mode -eq 'original') { Assert ((Get-FileHash -LiteralPath $completed.Path).Hash -eq $hash) 'Original audio bytes changed' }
            else { Assert (Test-Path -LiteralPath $source) 'Source removed before caller cleanup' }
            Remove-OwnStage $stage $workRoot
            Assert (-not (Test-Path -LiteralPath $stage)) 'Verified task was not cleaned'
        }
    }
}
Record 'Combined audio/video fallback preserves original codec' {
    $outDir = Join-Path $testRoot 'streamcopy'; [void][IO.Directory]::CreateDirectory($outDir)
    $stage = Join-Path $outDir ('job-' + [Guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($stage)
    $path = Join-Path $stage 'source.mp4'
    $result=Invoke-Native (Join-Path $root 'bin\ffmpeg.exe') @('-hide_banner','-v','error','-nostdin','-n','-f','lavfi','-i','color=size=32x32:rate=1','-i',$sources['mono44'],'-t','2','-c:v','mpeg4','-c:a','copy',$path)
    Assert-NativeSuccess $result 'Create muxed fixture'
    $config=Read-Configuration (Test-Config 'original' $outDir) $root
    $completed=Complete-Audio $root $config $path $stage '音视频分离'
    Assert ($completed.Final.Stream.codec_name -eq 'aac' -and @($completed.Final.Streams).Count -eq 1) 'Stream copy failed'
}
Record 'Failed verification retains downloaded source' {
    $outDir = Join-Path $testRoot 'failure'; [void][IO.Directory]::CreateDirectory($outDir)
    $stage = Join-Path $outDir 'bad-stage'; [void][IO.Directory]::CreateDirectory($stage)
    $path = Join-Path $stage 'source.webm'; Copy-Item -LiteralPath $sources['stereo48'] -Destination $path
    [IO.File]::WriteAllText((Join-Path $stage 'final.m4a'),'block conversion overwrite',$script:Utf8)
    $config=Read-Configuration (Test-Config 'alac' $outDir) $root
    $failed=$false; try { Complete-Audio $root $config $path $stage 'Should fail' | Out-Null } catch { $failed=$true }
    Assert $failed 'Conversion should fail with preexisting candidate'
    Assert (Test-Path -LiteralPath $path) 'Source was lost after failed conversion'
}
Record 'Reject sample rate/channel mismatch and corrupt output' {
    $source=Get-AudioProbe $root $sources['stereo48']; $other=Get-AudioProbe $root $sources['mono44']
    $rejected=$false; try { Assert-AudioParameters $source $other 'original' } catch { $rejected=$true }
    Assert $rejected 'Accepted different audio parameters'
    $broken=Join-Path $testRoot 'broken.m4a'; [IO.File]::WriteAllText($broken,'not audio',$script:Utf8)
    $rejected=$false; try { Test-FullDecode $root $broken } catch { $rejected=$true }
    Assert $rejected 'Accepted corrupt final file'
}
Record 'BAT entry processes invalid URL without unhandled exception' {
    $configPath=Test-Config 'alac' (Join-Path $testRoot 'bat-output')
    $bat=Join-Path $root 'MediaAudio.bat'
    $driver=Join-Path $testRoot 'test-bat-driver.bat'
    [IO.File]::WriteAllText($driver,('@echo off' + "`r`n" + 'call "' + $bat + '" -Url "not-a-video-url" -ConfigPath "' + $configPath + '" -NoPause' + "`r`n"),[Text.Encoding]::ASCII)
    $result=Invoke-Native $env:ComSpec @('/d','/c',$driver) -TimeoutSeconds 30
    Assert ($result.ExitCode -eq 1) 'Invalid URL returned wrong exit code'
    Assert (($result.StdOut -join ' ') -match 'Invalid video URL') 'BAT did not show clear error'
}
if ($Network) {
    foreach ($case in @(@('YouTube original',$YouTubeUrl,'original'),@('YouTube ALAC',$YouTubeUrl,'alac'),@('Bilibili ALAC',$BilibiliUrl,'alac'))) {
        Record $case[0] {
            $outDir=Join-Path $testRoot ($case[0].Replace(' ','-'))
            $configPath=Test-Config $case[2] $outDir
            $result=Invoke-Native (Join-Path $PSHOME 'powershell.exe') @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'MediaAudio.ps1'),'-Url',$case[1],'-ConfigPath',$configPath,'-NoPause') -ShowOutput -TimeoutSeconds 600
            Assert-NativeSuccess $result $case[0]
            Assert (($result.StdOut -join ' ') -match 'SUCCESS - ffprobe and full decode passed') 'Network test did not report verified success'
        }
    }
}
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $testRoot 'test-results.json') -Encoding UTF8
$results | Format-Table -AutoSize
Write-Host "Test report: $testRoot"
if (@($results | Where-Object { -not $_.Passed }).Count -gt 0) { exit 1 }
exit 0
