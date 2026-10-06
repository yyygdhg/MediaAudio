param([string]$OutputDirectory='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'MediaAudio.Core.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'dist'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$version=[IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid release version'}
$files=@(& git -C $root ls-files)
if($LASTEXITCODE -ne 0 -or $files.Count -lt 10){throw 'Build from a reviewed Git checkout with tracked source files'}
foreach($path in $files){
    if($path -match '(?i)(^|/)(cookies|logs|\.git)(/|$)|(^|/)config\.ini$|\.(exe|zip|webm|m4a|mp3|wav|flac|part)$|cookies.*\.txt$'){
        throw ('Private/runtime file is tracked: '+$path)
    }
}
$name='MediaAudio-v'+$version+'-Windows-x64.zip'
$final=Join-Path $OutputDirectory $name
$pending=Join-Path $OutputDirectory ('pending-'+[Guid]::NewGuid().ToString('N')+'.zip')
$zip=[IO.Compression.ZipFile]::Open($pending,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($path in $files){
        $entry='MediaAudio-v'+$version+'/'+$path.Replace('\','/')
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $root $path),$entry,[IO.Compression.CompressionLevel]::Optimal)
    }
    $entry=$zip.CreateEntry('MediaAudio-v'+$version+'/config.ini')
    $writer=New-Object IO.StreamWriter($entry.Open(),$script:Utf8)
    try {$writer.Write((Get-DefaultConfigText))}finally{$writer.Dispose()}
}finally{$zip.Dispose()}
Move-Item -LiteralPath $pending -Destination $final -Force
$digest=(Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'),$digest+'  '+$name+"`r`n",$script:Utf8)
Write-Host ('Built '+$final)
Write-Host ('SHA256: '+$digest)
