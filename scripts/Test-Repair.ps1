param([string]$Root='')
$ErrorActionPreference='Stop'
if (-not $Root) { $Root=Split-Path $PSScriptRoot -Parent }
. (Join-Path $Root 'scripts\MediaAudio.Core.ps1')
. (Join-Path $Root 'scripts\MediaAudio.Update.ps1')
$results=New-Object 'Collections.Generic.List[object]'
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; $results.Add([pscustomobject]@{Test=$Name;Passed=$true}) }
    catch { $results.Add([pscustomobject]@{Test=$Name;Passed=$false;Error=$_.Exception.Message}) }
}
Check 'Login/cookie instructions remain visible' {
    $text='Sign in to confirm you are not a bot. Use --cookies-from-browser or --cookies for authentication.'
    $safe=Protect-LogText $text
    Assert ($safe -match 'not a bot' -and $safe -match '--cookies-from-browser' -and $safe -notmatch 'Sensitive diagnostic omitted') 'Useful login diagnostic was hidden'
    $result=[pscustomobject]@{ExitCode=1;StdErr=@('ERROR: '+$text);StdOut=@()}
    $message=''; try { Assert-NativeSuccess $result 'Video extraction' } catch { $message=$_.Exception.Message }
    Assert ($message -match 'not a bot') 'Native error lost its actual cause'
}
Check 'Actual credentials and signed URLs stay redacted' {
    foreach ($text in @('Cookie: session=TOPSECRET','Authorization: Bearer TOPSECRET','password=TOPSECRET',
        'username=TOPSECRET','{"cookies":"TOPSECRET"}','https://user:TOPSECRET@example.org/watch?v=abc&token=TOPSECRET',
        'https://example.org/#access_token=TOPSECRET','logged in as TOPSECRET')) {
        Assert ((Protect-LogText $text) -notmatch 'TOPSECRET') "Credential leaked: $text"
    }
}
Check 'Official checksum accepts PowerShell byte-array response' {
    $digest=(Get-FileHash -LiteralPath (Join-Path $Root 'bin\yt-dlp.exe') -Algorithm SHA256).Hash
    $text=$digest.ToLowerInvariant() + '  yt-dlp.exe' + "`n" + ('a'*64) + '  yt-dlp_x86.exe' + "`n"
    Assert ((Get-YtDigest $text) -eq $digest) 'String checksum parse failed'
    Assert ((Get-YtDigest ([Text.Encoding]::UTF8.GetBytes($text))) -eq $digest) 'Binary response checksum parse failed'
    Assert-YtDigest (Join-Path $Root 'bin\yt-dlp.exe') $digest
}
Check 'Wrong hash rejected; installed executable unchanged' {
    $path=Join-Path $Root 'bin\yt-dlp.exe'; $before=(Get-FileHash -LiteralPath $path).Hash
    $rejected=$false; try { Assert-YtDigest $path ('0'*64) } catch { $rejected=$true }
    Assert $rejected 'Accepted corrupt update digest'
    Assert ((Get-FileHash -LiteralPath $path).Hash -eq $before) 'Installed executable changed after rejected verification'
}
Check 'Recent verified update skips repeated API requests' {
    $path=Join-Path $Root 'logs\update-state.json'
    $prior=$null; if (Test-Path -LiteralPath $path) { $prior=[IO.File]::ReadAllBytes($path) }
    $version=Invoke-Native (Join-Path $Root 'bin\yt-dlp.exe') @('--version')
    Assert-NativeSuccess $version 'Version check'
    $state=[pscustomobject]@{CheckedUtc=[DateTime]::UtcNow.ToString('o');Success=$true;InstalledVersion=($version.StdOut -join '').Trim()}
    [IO.File]::WriteAllText($path,($state|ConvertTo-Json),$script:Utf8)
    try {
        $status=Update-YtDlp $Root
        Assert ($status.Cached -and $status.Success) 'Verified update cache was not reused'
    }
    finally { if($null -ne $prior){[IO.File]::WriteAllBytes($path,$prior)} else {Remove-Item -LiteralPath $path -Force} }
}
Check 'Current configured cookies remain opt-in' {
    $temporaryConfig=Join-Path $Root 'logs\repair-defaults.ini'
    [IO.File]::WriteAllText($temporaryConfig,(Get-DefaultConfigText),$script:Utf8)
    try {
        $config=Read-Configuration $temporaryConfig $Root
        Assert (-not $config.cookies_from_browser) 'Defaults enabled browser cookies'
        Assert (-not $config.cookies_file) 'Defaults enabled local cookies'
        Assert (@(Get-YtArguments $Root $config) -contains '--no-cookies-from-browser') 'Default requests may access browser cookies'
    }
    finally { Remove-Item -LiteralPath $temporaryConfig -Force }
}
Check 'Explicit local Cookie file takes precedence without browser access' {
    $fixture=Join-Path $Root 'logs\repair-cookie-fixture.txt'
    $configPath=Join-Path $Root 'logs\repair-cookie-test.ini'
    [IO.File]::WriteAllText($fixture,"# Netscape HTTP Cookie File`r`n",$script:Utf8)
    [IO.File]::WriteAllText($configPath,((Get-DefaultConfigText).Replace('cookies_from_browser=','cookies_from_browser=chrome').Replace('cookies_file=','cookies_file=logs\repair-cookie-fixture.txt')),$script:Utf8)
    try {
        $config=Read-Configuration $configPath $Root
        $arguments=@(Get-YtArguments $Root $config)
        Assert ($arguments -contains '--cookies' -and $arguments -contains $fixture) 'Explicit file was not used'
        Assert ($arguments -contains '--no-cookies-from-browser' -and $arguments -notcontains '--cookies-from-browser') 'File mode attempted browser access'
        [IO.File]::WriteAllText($fixture,'invalid header',$script:Utf8)
        $rejected=$false; try { $null=Get-YtArguments $Root (Read-Configuration $configPath $Root) } catch { $rejected=$true }
        Assert $rejected 'Invalid Cookie file accepted'
        Remove-Item -LiteralPath $fixture -Force
        $rejected=$false; try { $null=Get-YtArguments $Root (Read-Configuration $configPath $Root) } catch { $rejected=$true }
        Assert $rejected 'Missing Cookie file accepted'
    }
    finally {
        foreach($path in @($fixture,$configPath)) { if(Test-Path -LiteralPath $path) {Remove-Item -LiteralPath $path -Force} }
    }
}
Check 'Anonymous requests ignore missing cookie file; login retry is selective' {
    $config=@{cookies_file=(Join-Path $Root 'logs\nonexistent-cookie-file.txt');cookies_from_browser='chrome'}
    $arguments=@(Get-YtArguments $Root $config -Anonymous)
    Assert ($arguments -contains '--no-cookies' -and $arguments -contains '--no-cookies-from-browser') 'Anonymous request uses authentication'
    Assert (Test-AuthenticationRequired 'Sign in to confirm you are not a bot') 'Did not identify authentication request'
    Assert (-not (Test-AuthenticationRequired 'HTTP Error 500: server unavailable')) 'Server failure incorrectly triggers Cookie access'
}
Check 'Metadata retries authorized authentication only when needed' {
    $fixture=Join-Path $Root 'logs\repair-retry-cookie.txt'
    [IO.File]::WriteAllText($fixture,"# Netscape HTTP Cookie File`r`n",$script:Utf8)
    function Invoke-Native {
        param([string]$Exe,[string[]]$Arguments,[int]$TimeoutSeconds)
        $script:MockArguments.Add($Arguments)
        $result=$script:MockResults[$script:MockArguments.Count-1]
        return $result
    }
    $success=[pscustomobject]@{ExitCode=0;StdOut=@('{}');StdErr=@()}
    $login=[pscustomobject]@{ExitCode=1;StdOut=@();StdErr=@('Sign in to confirm you are not a bot')}
    $server=[pscustomobject]@{ExitCode=1;StdOut=@();StdErr=@('HTTP Error 500: server unavailable')}
    try {
        foreach($case in @('anonymous-success','login-configured','login-unconfigured','server-error')) {
            $config=@{cookies_file=$fixture;cookies_from_browser=''}
            $script:MockArguments=New-Object 'Collections.Generic.List[object]'
            $script:MockResults=@($success)
            $expectedCalls=1
            if($case -eq 'login-configured') {$script:MockResults=@($login,$success);$expectedCalls=2}
            if($case -eq 'login-unconfigured') {$script:MockResults=@($login);$config.cookies_file=''}
            if($case -eq 'server-error') {$script:MockResults=@($server)}
            $extraction=Get-MetadataWithAuthentication $Root $config @('--skip-download','https://example.org/video')
            Assert ($script:MockArguments.Count -eq $expectedCalls) ('Unexpected retry count: '+$case)
            Assert ($script:MockArguments[0] -contains '--no-cookies') ('First request used cookies: '+$case)
            Assert ($extraction.CookiesUsed -eq ($expectedCalls -eq 2)) ('Incorrect Cookie status: '+$case)
            if($expectedCalls -eq 2) {Assert ($extraction.Arguments -contains '--cookies' -and $script:MockArguments[1] -contains $fixture) 'Retry did not use explicitly authorized file'}
        }
    }
    finally {Remove-Item -LiteralPath $fixture -Force}
}
$report=Join-Path $Root 'logs\repair-unit-tests.json'
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $report -Encoding UTF8
$results | Format-Table -AutoSize
if (@($results | Where-Object {-not $_.Passed}).Count) { exit 1 }
