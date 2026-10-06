# Downloads unmodified dependencies from upstream. No third-party EXEs are shipped.
# Windows PowerShell 5.1; UTF-8 BOM. Requires MediaAudio.Core.ps1.
function Resolve-ContainedPath([string]$Parent, [string]$Relative) {
    if (-not $Relative -or [IO.Path]::IsPathRooted($Relative)) { throw 'Expected a relative dependency path.' }
    $prefix = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    $path = [IO.Path]::GetFullPath((Join-Path $Parent $Relative))
    if (-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Dependency path escapes its directory.' }
    return $path
}
function Assert-DependencyUrl([string]$Url) {
    $uri = $null
    if (-not [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or
        $uri.Host -notin @('github.com','raw.githubusercontent.com','nodejs.org','www.gyan.dev') -or $uri.UserInfo) {
        throw 'Dependency download must use an approved upstream HTTPS host.'
    }
}
function Assert-DependencyHash([string]$Path, [string]$Hash) {
    if ($Hash -notmatch '^[0-9A-Fa-f]{64}$' -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Hash) {
        throw 'Dependency SHA256 mismatch. No downloaded executable will be installed.'
    }
}
function Get-DependencyFile([string]$Url, [string]$Hash, [string]$Destination) {
    Assert-DependencyUrl $Url
    $priorProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination -TimeoutSec 300
        Assert-DependencyHash $Destination $Hash
    }
    finally { $ProgressPreference = $priorProgress }
}
function Expand-SelectedDependency([string]$ArchivePath, $Files, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($file in $Files) {
            $matches = @($archive.Entries | Where-Object { $_.FullName -ceq $file.entry })
            if ($matches.Count -ne 1 -or -not $matches[0].Name) { throw 'Dependency archive does not contain the expected file exactly once.' }
            $path = Resolve-ContainedPath $Destination $file.destination
            [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($matches[0],$path,$false)
        }
    }
    finally { $archive.Dispose() }
}
function Read-DependencyLock([string]$Root) {
    $manifest = [IO.File]::ReadAllText((Join-Path $Root 'dependencies.lock.json')) | ConvertFrom-Json
    if ($manifest.schema_version -ne 1 -or $manifest.platform -ne 'windows-x64') { throw 'Unsupported dependency lock format.' }
    $packages = @($manifest.packages)
    if ($packages.Count -ne 3 -or @($packages.name | Select-Object -Unique).Count -ne 3) { throw 'Expected exactly three dependency packages.' }
    foreach ($package in $packages) {
        if ($package.name -notin @('yt-dlp','ffmpeg','node') -or $package.format -notin @('file','zip') -or $package.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Invalid dependency lock entry.' }
        Assert-DependencyUrl $package.url
        foreach ($file in $package.files) { [void](Resolve-ContainedPath (Join-Path $Root 'bin') $file.destination) }
        foreach ($notice in $package.notices) {
            Assert-DependencyUrl $notice.url
            if ($notice.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Invalid notice checksum.' }
            [void](Resolve-ContainedPath (Join-Path $Root 'bin') $notice.destination)
        }
    }
    return $manifest
}
function Ensure-Dependencies([string]$Root) {
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'MediaAudio v0.1.0 requires 64-bit Windows.' }
    $required = @('yt-dlp.exe','ffmpeg.exe','ffprobe.exe','node.exe')
    $bin = Join-Path $Root 'bin'
    [void][IO.Directory]::CreateDirectory($bin)
    if ((Get-Item -LiteralPath $bin).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Dependency directory must not be redirected.' }
    if (@($required | Where-Object {-not (Test-Path -LiteralPath (Join-Path $bin $_) -PathType Leaf)}).Count -eq 0) { return }
    $logs = Join-Path $Root 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    if ((Get-Item -LiteralPath $logs).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Setup directory must not be redirected.' }
    $lock = $null; $pending = $null
    try {
        $lock = [IO.File]::Open((Join-Path $logs 'setup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $manifest = Read-DependencyLock $Root
        $pending = Join-Path $logs ('setup-' + [Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($pending)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Host 'First-time setup / 首次准备：下载并校验上游依赖。无需管理员权限。'
        Write-Host 'The v0.1.0 ZIP contains project scripts; dependencies stay local after setup.'
        foreach ($package in $manifest.packages) {
            $executables = @($package.files | Where-Object { $_.destination -match '\.exe$' })
            if (@($executables | Where-Object {-not (Test-Path -LiteralPath (Resolve-ContainedPath $bin $_.destination) -PathType Leaf)}).Count -eq 0) { continue }
            Write-Host "Preparing $($package.name) $($package.version)..."
            $packageStage = Join-Path $pending $package.name
            [void][IO.Directory]::CreateDirectory($packageStage)
            $download = Join-Path $pending ($package.name + '.download')
            Get-DependencyFile $package.url $package.sha256 $download
            if ($package.format -eq 'zip') { Expand-SelectedDependency $download $package.files $packageStage }
            else {
                if (@($package.files).Count -ne 1) { throw 'A direct dependency must contain one file.' }
                $path = Resolve-ContainedPath $packageStage $package.files[0].destination
                [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
                Copy-Item -LiteralPath $download -Destination $path
            }
            foreach ($notice in $package.notices) {
                $path = Resolve-ContainedPath $packageStage $notice.destination
                [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
                Get-DependencyFile $notice.url $notice.sha256 $path
            }
            foreach ($file in $executables) {
                $path = Resolve-ContainedPath $packageStage $file.destination
                $arg = '-version'; if ($file.destination -in @('node.exe','yt-dlp.exe')) { $arg = '--version' }
                Assert-NativeSuccess (Invoke-Native $path @($arg) -TimeoutSeconds 30) 'Dependency executable verification'
            }
            foreach ($file in (@($package.files) + @($package.notices))) {
                $target = Resolve-ContainedPath $bin $file.destination
                if (Test-Path -LiteralPath $target) { continue }
                $directory = Split-Path $target -Parent
                [void][IO.Directory]::CreateDirectory($directory)
                if ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Dependency target directory must not be redirected.' }
                [IO.File]::Move((Resolve-ContainedPath $packageStage $file.destination),$target)
            }
            Write-Host "$($package.name): verified and ready."
            Write-Log "Dependency prepared from pinned upstream release: $($package.name) $($package.version)"
        }
        foreach ($name in $required) { if (-not (Test-Path -LiteralPath (Join-Path $bin $name) -PathType Leaf)) { throw "Setup incomplete: missing $name." } }
    }
    finally {
        if ($pending -and (Test-Path -LiteralPath $pending)) {
            $prefix = [IO.Path]::GetFullPath($logs).TrimEnd('\') + '\'
            $full = [IO.Path]::GetFullPath($pending)
            if ($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $full -Leaf) -match '^setup-[0-9a-f]{32}$' -and
                -not ((Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if ($null -ne $lock) { $lock.Dispose() }
    }
}
