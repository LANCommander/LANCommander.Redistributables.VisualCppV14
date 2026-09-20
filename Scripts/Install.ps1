#Requires -RunAsAdministrator

# Installs the Microsoft Visual C++ v14 runtime for each selected architecture.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\Files\
# -- containing vc_redist.x86.exe, vc_redist.x64.exe and LICENSE.txt.
#
# Elevation is genuine: these installers write into System32 and the machine-wide
# registry. The directive above is stripped at packaging time and recorded as
# RequiresAdmin on the manifest, which is what drives the UAC prompt on the client.

$ErrorActionPreference = 'Stop'

# The cmdlet writes a non-terminating error when the game manifest has no entry
# for this redistributable. Both is the right answer in that case -- it is never
# wrong, only occasionally more than necessary -- so the lookup is not allowed to
# fail the script.
$options = Get-RedistributableOptions -Path $InstallDirectory -Id $GameManifest.Id `
    -Name 'Visual C++ v14 Redistributable (2015-2022)' -ErrorAction SilentlyContinue

$architecture = if ($options -and $options.Architecture) { ([string] $options.Architecture).ToLowerInvariant() } else { 'both' }

if ($architecture -eq 'auto') {
    $executable = $GameManifest.Actions |
        Where-Object { $_.IsPrimaryAction } |
        Select-Object -First 1 -ExpandProperty Path

    if ($executable) { $executable = $executable.Replace('{InstallDir}', $InstallDirectory) }

    # Unreadable executable falls back to both rather than guessing. Installing a
    # runtime that turns out to be unnecessary costs a little disk; skipping the one
    # the game needs costs a launch failure.
    $architecture = 'both'

    if ($executable -and (Test-Path -LiteralPath $executable)) {
        $stream = [System.IO.File]::OpenRead($executable)

        try {
            $reader = [System.IO.BinaryReader]::new($stream)
            $stream.Position = 0x3C
            $stream.Position = $reader.ReadInt32() + 4
            $machine = $reader.ReadUInt16()

            # 0x8664 x64, 0xAA64 ARM64 -- Microsoft's x64 package carries the ARM64
            # binaries too, so both map to x64. 0x014C is x86, and is also what a
            # managed AnyCPU executable reports even though it runs 64-bit; those
            # games should be set to Both explicitly.
            $architecture = if ($machine -eq 0x8664 -or $machine -eq 0xAA64) { 'x64' } else { 'x86' }
        }
        finally {
            $stream.Dispose()
        }
    }
}

$required = switch ($architecture) {
    'x86' { @('x86') }
    'x64' { @('x64') }
    default { @('x86', 'x64') }
}

# 0     installed.
# 1638  a newer version of this runtime is already present. Microsoft's own
#       documentation calls this out: the package refuses to downgrade and returns
#       an error, and the caller is expected to treat it as "already satisfied".
#       Burn sometimes surfaces it as the HRESULT 0x80070666 instead.
# 3010  installed, reboot pending.
# 1641  installed, reboot already initiated.
$acceptable = @(0, 1638, -2147023294, 3010, 1641)

$Return = 0

foreach ($arch in $required) {
    $installer = ".\vc_redist.$arch.exe"

    if (-not (Test-Path -LiteralPath $installer)) {
        # The payload no longer matches what this script expects, which is a
        # packaging fault rather than a machine problem. Report it as ERROR_FILE_NOT_FOUND.
        Write-Warning "$installer is missing from the redistributable payload"
        if ($Return -eq 0) { $Return = 2 }
        continue
    }

    Write-Host "Installing Microsoft Visual C++ v14 runtime ($arch)"

    $process = Start-Process -FilePath $installer -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    $code = $process.ExitCode

    if ($acceptable -contains $code) {
        if ($code -eq 1638 -or $code -eq -2147023294) {
            Write-Host "A newer Visual C++ v14 runtime ($arch) is already installed; nothing to do"
        }
        elseif ($code -eq 3010 -or $code -eq 1641) {
            Write-Host "Visual C++ v14 runtime ($arch) installed; a reboot is pending"
        }

        continue
    }

    Write-Warning "vc_redist.$arch.exe exited with $code"

    # Every requested architecture is attempted even after one fails, so a partly
    # installed machine shows up in the log rather than stopping silently at the
    # first problem. The first real failure is what gets reported back.
    if ($Return -eq 0) { $Return = $code }
}
