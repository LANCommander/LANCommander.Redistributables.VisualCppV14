# LANCommander.Redistributables.VisualCppV14

Automatically built LANCommander redistributable import package (`.LCX`) for the
[Microsoft Visual C++ v14 Redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).

The Microsoft Visual C++ runtime libraries, v14. One package covers every v14
toolset — anything built with Visual Studio 2015 through 2022, and in practice 2026
as well, since the runtime stays binary compatible back to 2015. This is the single
most common missing dependency for games of that era, usually surfacing as
`MSVCP140.dll was not found` or `VCRUNTIME140.dll is missing` on launch.

Both architectures are bundled. By default each client installs only the one the
game's executable actually needs; set the `Architecture` option to **Both** for
.NET AnyCPU games, which report as 32-bit but run 64-bit — see
[Options](#options).

> **Read [`LICENSES/NOTICE.md`](LICENSES/NOTICE.md) before relying on this
> package.** Microsoft's terms for the standalone redistributable do not grant
> redistribution rights, and bundling the installers here is a deliberate decision
> taken with that in view rather than a permission we hold.

## Install it

Download the `.lcx` asset from the [latest release][latest] and import it
through your LANCommander server's **Redistributables** page, or from the CLI:

```
LANCommander.Launcher.CLI Import --Path LANCommander.Redistributables.VisualCppV14-v<version>.lcx --Type Redistributable
```

Then assign it to the games that need it, either from the game's
**Redistributables** field or from this redistributable's **Games** field.

Re-importing a newer release **updates** the existing entry rather than creating a
second one, because the identifiers in `redistributable.yml` are stable across
releases.

Alternatively, import once and let it update itself: the package ships a
`Package` script, which a LANCommander server runs on a schedule to pull new
versions straight from this repository's releases.

[latest]: https://github.com/LANCommander/LANCommander.Redistributables.VisualCppV14/releases/latest

## What is in the package

| Path | |
|---|---|
| `Manifest.yml` | Redistributable metadata, including the embedded option schema |
| `Archives/{guid}` | A ZIP of `vc_redist.x86.exe`, `vc_redist.x64.exe` and `LICENSE.txt`, extracted into the game's `.lancommander` metadata directory |
| `Scripts/{guid}` | One entry per PowerShell script |

ARM64 is deliberately not packaged. Microsoft's x64 installer already contains the
ARM64 binaries, so a separate `vc_redist.arm64.exe` would add weight to every
package for nothing.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `Architecture` | choice — `both`, `auto`, `x86`, `x64` | `auto` | Which runtime to install. The default, **Match the game executable**, reads the game's PE header and installs only the runtime it actually needs. There is one case it gets wrong: a .NET AnyCPU executable reports as 32-bit even though it runs 64-bit, so set those games to **Both**. **Both** is also the right answer whenever you are unsure — 64-bit Windows still needs the x86 runtime because most games of this era are 32-bit, and installing both is never wrong, only occasionally more than necessary. |

Administrators can override this per game from the game's **Redistributables**
page. Values resolve as schema default, then per-game value, then per-action
override.

## How this repository works

| File | Purpose |
|---|---|
| `redistributable.yml` | Identity, download permalinks, stable script GUIDs |
| `source.ps1` | Downloads both installers and reads the version off the PE resource |
| `Schema.Overlay.yml` | The whole option schema, written by hand — there is no config file to parse |
| `OptionSchema.yml` | Built from the overlay. Do not edit by hand |
| `Scripts/*.ps1` | Client-side and server-side scripts |
| `LICENSES/` | Upstream attribution and license text |

`OptionSchema.yml` is generated, and the build fails if the committed copy does
not match what the overlay produces. To regenerate it locally:

```powershell
Import-Module <path-to>/LANCommander.Redistributables/module/LANCommander.Redistributables
Invoke-RedistributableBuild -RepositoryPath . -UpdateSchema
```

Edit `Schema.Overlay.yml` to change how the option is presented; never edit
`OptionSchema.yml`, since the next rebuild overwrites it.

### How detection and install work

`DetectInstall` reads `Version` and `Installed` from
`HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\{x86,x64}` — and the
`WOW6432Node` mirror, since which of the two is visible depends on the bitness of
the host PowerShell. It reports "installed" only when every selected architecture
is present *and* at least as new as the build this package carries. That matters
because Microsoft's installer refuses to downgrade and returns an error when a
newer runtime is already present.

`Install` runs each installer with `/install /quiet /norestart` and treats `1638`
(a newer version is already installed, also seen as `0x80070666`), `3010` and
`1641` (reboot pending or initiated) as success alongside `0`.

`Uninstall` deliberately does nothing. The runtime is shared machine-wide and
other software depends on it.

### Staying current

Microsoft publishes no version number and no release feed for this package — their
own documentation tells you to download the installer and read **File version** off
its properties. `source.ps1` does exactly that, reading the PE version resource of
`vc_redist.x64.exe`.

A scheduled workflow checks for new versions daily. When one appears it opens a
pull request bumping `LastKnownVersion`; merging it publishes the release.

### Deriving another Visual C++ version

This repository is the model for the other VC++ runtimes. See
[`template-vcredist/`](https://github.com/LANCommander/LANCommander.Redistributables/tree/main/template-vcredist)
in the hub, which is derived from it.

## Licensing

The scripts and workflows here are MIT licensed. The redistributed payload is not
ours — see [`LICENSES/NOTICE.md`](LICENSES/NOTICE.md) for attribution, the full
terms, and the reasoning behind how this package is distributed.
