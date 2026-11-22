# Handoff: packaging Microchip Libero SoC for Arch Linux

Briefing for an AI coding agent that picks up this work: the rules, the goal
and the owner's decisions. Read this file first, then the others as needed.

Written 2026-11-12 for the repository owner, split into several files on
2026-11-17.

| File | Content | Former sections |
|---|---|---|
| handoff.md (this file) | Rules, goal, decisions taken | 0, 1, 1a |
| [findings.md](findings.md) | What is known about the installer, run-time fixes, licensing, programmer and desktop integration | 2 to 7, 11 |
| [design.md](design.md) | Package contents, shim options, decisions left open | 8, 10 |
| [test-plan.md](test-plan.md) | Path from the working install to a reproducible one, and the list of what is still to be verified | 9 |

Section numbers are kept across the files, so "section 4" means the same
everywhere.

Machine-specific and personal values (hostname, user name, MAC addresses,
licence identifiers, serial numbers) are **not** in these files. They live in
`local/machine-private.md`, which must never be committed. Placeholders such
as `<wifi-mac>` refer to entries in that file.

## Status (2026-11-22)

- Both packages exist and run on the owner's machine: `libero-flexlm` (the
  licence server, `flexlm/`) and `libero-soc` (setup tool, wrapper, shims,
  `soc/`). The owner's hand-made install and manual fixes are gone; Libero
  2026.1 was installed through `sudo libero-setup install` on 2026-11-18,
  and Libero with simulation works from it (findings.md section 3).
- `libero-soc` 0.2.0 supports several Libero versions side by side and
  writes Microchip's four menu entries per version; installed on the
  owner's machine on 2026-11-22, where the upgrade migrated the existing
  install and the entries appear.
- The licence server recovered from a reproduced MAC-race failure by itself
  within about a minute (section 5).
- Not published: nothing is on the AUR yet, and the packages build from this
  checkout, not from a release tarball.

Open, in rough order:

- Deferred tests: the progress display on a real install; the browser
  hand-off on other desktops. Done since: the programmer is found from the
  root-owned install (2026-11-20), the licence server was healthy after two
  days of normal use, all four menu entries start their tools, and
  `libero-setup remove` worked on the real install (2026-11-22).
- Side-by-side versions: built in 0.2.0, but only tested with stubs; a real
  second version needs a second Libero release, and its download link and
  checksum added to `libero-setup`.
- A test on plain Arch, ideally a VM with a desktop: `gtk2` and
  `ncurses5-compat-libs` come from the AUR there, `multilib` must be enabled,
  and fonts and the kernel's `ftdi_sio` match are unchecked (findings.md
  section 3, "Plain Arch compared with CachyOS").
- Publishing: release tarball as PKGBUILD source. The names `libero-soc` and
  `libero-flexlm` are free on the AUR (checked 2026-11-20).
- The ArchWiki article, see the notes below.

## Notes for the ArchWiki article

Collected wishes of the owner for the update of
<https://wiki.archlinux.org/title/Libero>:

- Describe offline use as well (2026-11-19): a machine without internet
  access, or without a browser session. That covers getting the web
  installer on another machine and passing it with
  `libero-setup install --installer FILE`; what the installer itself still
  needs from the network (it downloads 12.5 GB from Microchip's repository;
  the vendor's `create-offline` command is untested); the IP MegaVault
  component for IP cores without internet, which `libero-setup` does not
  install; and that the licence server is local and needs no network once the
  licence file is there.

## 0. How to read this document

Every claim carries a confidence tag. Do not treat lower tiers as fact.

| Tag | Meaning |
|---|---|
| **[verified]** | Observed on the target machine (command output or log seen) |
| **[doc]** | Stated in Microchip / Flexera / ArchWiki documentation |
| **[inferred]** | Reasoned from evidence, never directly confirmed |
| **[untested]** | Proposed, never run. Test before relying on it |

Rules for the agent:

- Never download, mirror or commit Microchip binaries, daemons or `License.dat`.
- Privacy: `local/` is private. Before the first commit, add `local/` to
  `.gitignore` and confirm with `git check-ignore -v local/machine-private.md`.
  Read that file when a real value is needed; never copy its values into
  tracked files, commit messages, issues or logs pasted into the repo.
- Before every commit, scan staged changes for personal data: MAC addresses
  and FlexLM hostids (12 hex digits), host and user names, `/home/<user>`
  paths, e-mail addresses, licence `SIGN=` values, software/site ids, serial
  numbers, UUIDs from installer caches. Replace hits with placeholders. A
  starting point:
  `git diff --cached | grep -nEi '([0-9a-f]{2}:){5}[0-9a-f]{2}|\b[0-9a-f]{12}\b|/home/[a-z]|SIGN=|@[a-z0-9.-]+\.[a-z]{2,}'`
- When pasting command output into tracked docs, redact first. New personal
  values discovered during the work go into `local/machine-private.md`.
- Do not modify `/opt/microchip` on the working machine without asking. It is
  the owner's working install.
- Section 9, in [test-plan.md](test-plan.md), lists what must be verified
  first. Start there, one item at a time.

## 1. Goal and non-goals

Goal: a reproducible way to install and run Libero SoC on Arch, good enough to
publish on the AUR, and an update for the stale ArchWiki page.

Non-goals: redistributing vendor software; supporting licence tiers other than
the free Silver floating licence; SoftConsole (separate product, no licence).

## 1a. Decisions taken by the owner (2026-11-12)

These are settled. Do not reopen them; implement them.

| Topic | Decision |
|---|---|
| Architecture | Helper package. pacman owns only wrapper, units, rules, setup tool. The vendor web installer is run headlessly by the setup tool into `/opt/microchip`. No repackaging of the vendor tree, no container. |
| Components | `Libero_SoC` only. **No** SmartHLS, **no** MegaVault. IP cores download on demand into `/opt/microchip/common/vault` (user data, not packaged). |
| Licence server | Its own package, `libero-flexlm` (changed 2026-11-17; before that: part of the same package). **System** unit, dedicated system user `libero-flexlm`, daemons taken from `<install>/LicenseDaemons/`. Start gate, watchdog timer and restart after resume shipped by default. Licence request itself stays manual. |
| Setup runs as | root. `/opt/microchip` root-owned like any package content. |
| Repo licences | 0BSD for the files submitted to the AUR (PKGBUILD, `.SRCINFO`, `.install`); AGPL-3.0-or-later for scripts; CC BY-SA 4.0 for prose. Use `REUSE.toml` to declare per-path. |
| Privacy | `local/` gitignored; see rules in section 0. |
| Disk | The user's filesystem is unknown; do not rely on btrfs compression or any filesystem feature. Peak during setup is roughly download (12.5 GB) plus install (36 GB), i.e. about 13 GB above the final size. |
| Scan-MAC randomisation | Stays enabled by default; disabling it is opt-in documentation only. |
| Versions (2026-11-18) | One `libero-soc` package. One Libero version at a time for now; side-by-side installs of 2026.1 and newer (headless-capable installers only) are a later extension of `libero-setup` and the wrapper. |
| `/etc` files (2026-11-18) | The package owns `/etc/redhat-release` and `/etc/pki/tls/certs/ca-bundle.crt`. `/etc/cyusb.conf` stays the vendor's file; `libero-setup remove` cleans it up. The vendor's `88-cyusb.rules` is deleted after every install. |
| Installer download (2026-11-18) | Microchip serves the web installer only to a signed-in account. `libero-setup install` opens the link in the user's browser, waits for the file in the user's download folder, verifies its pinned SHA-256 and continues. No handling of Microchip credentials; not in the PKGBUILD. `--installer FILE` remains for offline use. |
| IP vault (2026-11-18) | Per user (`~/.actel/vault`, Libero's own fallback); no shared, group-writable vault. |
