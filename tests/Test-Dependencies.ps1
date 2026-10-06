$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\MediaAudio.Core.ps1')
. (Join-Path $root 'scripts\MediaAudio.Dependencies.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$testRoot=Join-Path $root ('logs\dependency-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$results=New-Object 'Collections.Generic.List[object]'
function Assert([bool]$Condition,[string]$Message) {if(-not $Condition){throw $Message}}
function Check([string]$Name,[scriptblock]$Body) {
    try {& $Body;$results.Add([pscustomobject]@{Test=$Name;Passed=$true})}
    catch {$results.Add([pscustomobject]@{Test=$Name;Passed=$false;Error=$_.Exception.Message})}
}
Check 'Pinned lock specifies three upstream packages and hashes' {
    $lock=Read-DependencyLock $root
    Assert (@($lock.packages).Count -eq 3) 'Incomplete dependency manifest'
    Assert (@($lock.packages|Where-Object {$_.sha256 -notmatch '^[A-F0-9]{64}$'}).Count -eq 0) 'Unpinned package'
}
Check 'Download rejects non-HTTPS, unapproved hosts and embedded credentials' {
    foreach($url in @('http://nodejs.org/a.zip','https://example.org/a.exe','https://secret@github.com/a.exe')) {
        $rejected=$false;try {Assert-DependencyUrl $url}catch{$rejected=$true}
        Assert $rejected 'Unsafe source accepted'
    }
}
Check 'Dependency target paths cannot escape their parent' {
    foreach($path in @('..\outside.exe','C:\outside.exe','')) {
        $rejected=$false;try {$null=Resolve-ContainedPath $testRoot $path}catch{$rejected=$true}
        Assert $rejected 'Unsafe target accepted'
    }
    Assert ((Resolve-ContainedPath $testRoot 'licenses\notice.txt').StartsWith($testRoot+'\')) 'Valid nested path rejected'
}
Check 'Corrupt download is refused before installation' {
    $fixture=Join-Path $testRoot 'fixture.txt';[IO.File]::WriteAllText($fixture,'fixture')
    $actual=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
    Assert-DependencyHash $fixture $actual
    $rejected=$false;try {Assert-DependencyHash $fixture ('0'*64)}catch{$rejected=$true}
    Assert $rejected 'Corrupt digest accepted'
    Assert ((Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -eq $actual) 'Verification changed the source'
}
Check 'ZIP selects exact entries and refuses escaping output paths' {
    $zipPath=Join-Path $testRoot 'fixture.zip';$zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach($name in @('package/notice.txt','../outside.txt')) {
            $entry=$zip.CreateEntry($name);$writer=New-Object IO.StreamWriter($entry.Open())
            try {$writer.Write('fixture')}finally{$writer.Dispose()}
        }
    }finally{$zip.Dispose()}
    $destination=Join-Path $testRoot 'extract'
    Expand-SelectedDependency $zipPath @([pscustomobject]@{entry='package/notice.txt';destination='licenses\notice.txt'}) $destination
    Assert (Test-Path -LiteralPath (Join-Path $destination 'licenses\notice.txt')) 'Expected file not extracted'
    Assert (-not (Test-Path -LiteralPath (Join-Path $testRoot 'outside.txt'))) 'Unselected traversal entry extracted'
    $rejected=$false
    try {Expand-SelectedDependency $zipPath @([pscustomobject]@{entry='package/notice.txt';destination='..\outside.txt'}) $destination}catch{$rejected=$true}
    Assert $rejected 'Escaping extraction target accepted'
}
Check 'A prepared portable folder performs no setup or downloads' {
    $prepared=Join-Path $testRoot 'prepared';$bin=Join-Path $prepared 'bin';[void][IO.Directory]::CreateDirectory($bin)
    foreach($name in @('yt-dlp.exe','ffmpeg.exe','ffprobe.exe','node.exe')) {[IO.File]::WriteAllText((Join-Path $bin $name),'fixture')}
    function Read-DependencyLock {throw 'Existing tools must not cause network setup'}
    Ensure-Dependencies $prepared
    Assert (-not (Test-Path -LiteralPath (Join-Path $prepared 'logs'))) 'Prepared folder unexpectedly started setup'
}
$results|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $root 'logs\dependency-tests.json') -Encoding UTF8
$results|Format-Table -AutoSize
if(@($results|Where-Object {-not $_.Passed}).Count){exit 1}
