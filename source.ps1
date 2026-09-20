<#
.SYNOPSIS
    Resolves and downloads the upstream Visual C++ v14 Redistributable installers.
.DESCRIPTION
    Contract:
      -CheckOnly            write the upstream version to stdout and exit.
      -OutputPath <dir>     download the installers there, then emit a JSON object
                            with Version and optionally Changelog.

    Microsoft publishes no version number for this package anywhere. There is no
    release feed, and the download page deliberately omits the version because the
    package is updated frequently -- their own instructions are to download the
    installer and read "File version" off its properties in Explorer. So none of
    Resolve-UpstreamVersion's resolvers apply and the version is read out of the
    downloaded installer's PE version resource instead.

    The installers are copied in byte-for-byte under their original filenames.
    Microsoft's terms require the software to be unmodified wherever it travels, so
    nothing here repacks, extracts or renames them.

    Changelog is deliberately null. Microsoft publishes no per-build changelog at a
    stable URL, and inventing one would put fiction in every release body.
#>
[CmdletBinding(DefaultParameterSetName = 'Download')]
param(
    [Parameter(ParameterSetName = 'Check')][switch] $CheckOnly,
    [Parameter(ParameterSetName = 'Download', Mandatory)][string] $OutputPath
)

$ErrorActionPreference = 'Stop'

$definition = Get-RedistributableDefinition -Path $PSScriptRoot
$source = $definition['Source']

$downloads = $source['Downloads']

if (-not $downloads -or $downloads.Count -eq 0) {
    throw 'Source.Downloads in redistributable.yml lists no installers to fetch'
}

$versionFrom = [string] $source['VersionFrom']

if (-not $downloads.Contains($versionFrom)) {
    throw "Source.VersionFrom is '$versionFrom' but Source.Downloads has no such entry"
}

<#
.SYNOPSIS
    Reads the four-part file version out of a Windows PE image.
.DESCRIPTION
    FileVersionInfo parses the PE version resource directly rather than asking the
    OS, so this works on the Linux build runner as well as on Windows. An empty
    result means the download was not a PE at all -- almost certainly an HTML error
    page saved under a .exe name, which is what a broken aka.ms redirect looks like.
#>
function Get-InstallerVersion {
    param([Parameter(Mandatory)][string] $Path)

    $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path).FileVersion

    if ([string]::IsNullOrWhiteSpace($version)) {
        $size = (Get-Item -LiteralPath $Path).Length
        throw "No PE version resource in '$Path' ($size bytes); the download did not return an installer"
    }

    return $version.Trim()
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) "vcredist-$([guid]::NewGuid())"
$null = New-Item -ItemType Directory -Path $temp -Force

try {
    # -CheckOnly runs daily from the scheduled upstream check, so it fetches only
    # the one installer the version is taken from rather than all of them.
    $wanted = if ($CheckOnly) { @($versionFrom) } else { @($downloads.Keys) }

    $versions = [ordered] @{}

    foreach ($architecture in $wanted) {
        $url = [string] $downloads[$architecture]
        $file = Join-Path $temp "vc_redist.$architecture.exe"

        Write-Verbose "Downloading $url"
        Invoke-WebRequest -Uri $url -OutFile $file -MaximumRetryCount 3 -RetryIntervalSec 5

        $versions[$architecture] = Get-InstallerVersion -Path $file
    }

    $version = $versions[$versionFrom]

    # Microsoft ships every architecture of a given build together, so a mismatch
    # means one of the permalinks is serving a stale file. Worth seeing in the build
    # log, but not worth failing over -- the package is still coherent, it just
    # carries two builds.
    foreach ($architecture in $versions.Keys) {
        if ($versions[$architecture] -ne $version) {
            Write-Warning "vc_redist.$architecture.exe is $($versions[$architecture]) but the package is stamped $version from $versionFrom"
        }
    }

    if ($CheckOnly) {
        Write-Output $version
        return
    }

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        $null = New-Item -ItemType Directory -Path $OutputPath -Force
    }

    foreach ($architecture in $downloads.Keys) {
        Copy-Item -LiteralPath (Join-Path $temp "vc_redist.$architecture.exe") -Destination $OutputPath -Force
    }

    # The terms have to reach the machine the software is installed on, not just
    # this repository.
    $license = Join-Path $PSScriptRoot 'LICENSES/UPSTREAM-LICENSE.txt'

    if (Test-Path -LiteralPath $license) {
        Copy-Item -LiteralPath $license -Destination (Join-Path $OutputPath 'LICENSE.txt') -Force
    }
    else {
        throw 'LICENSES/UPSTREAM-LICENSE.txt is missing; the license text must ship with the installers'
    }

    @{
        Version   = $version
        Changelog = $null
    } | ConvertTo-Json -Compress | Write-Output
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
