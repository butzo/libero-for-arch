# libero-for-arch

Running Microchip Libero SoC on Arch Linux: a helper package for the AUR and
the notes behind it.

**Status: work in progress.** Nothing here is installable yet. Start with
[docs/handoff.md](docs/handoff.md) (rules, goal, decisions); the findings so
far are in [docs/findings.md](docs/findings.md), the package design in
[docs/design.md](docs/design.md) and the open verification steps in
[docs/test-plan.md](docs/test-plan.md).

## What this will be

A package that ships only its own files (launcher wrapper, setup tool, systemd
units for the FlexLM licence server, udev rules, desktop entry). The vendor
software is installed by the setup tool, which runs Microchip's own web
installer into `/opt/microchip`. This repository contains no Microchip
binaries, licence files or installer scripts, and never will.

Libero SoC is proprietary software and not officially supported on Arch. You
need your own licence from Microchip to run it.

## Repository layout

| Path | Content |
|---|---|
| `docs/` | Findings, design decisions, verification list |
| `aur/` | PKGBUILD and install script (planned) |
| `LICENSES/` | Licence texts |
| `.githooks/` | Pre-commit scan for personal data |
| `local/` | Private machine-specific notes, gitignored |

## Contributing

Enable the pre-commit scan once after cloning:

```sh
ln -s ../../.githooks/pre-commit .git/hooks/pre-commit
```

It blocks commits that contain MAC addresses, FlexLM hostids, home paths,
licence signatures or e-mail addresses. Redact command output before pasting
it into tracked files.

## Licence

Declared per path in [REUSE.toml](REUSE.toml): 0BSD for the files submitted to
the AUR, AGPL-3.0-or-later for scripts, CC BY-SA 4.0 for documentation.
