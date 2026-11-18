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

## Status (2026-11-18)

- The owner's hand-made install runs the whole flow on CachyOS: synthesis,
  place and route, bitstream generation, programming, and simulation started
  from Libero. Details in sections 4 to 7.
- The licence server is its own package, `libero-flexlm`, installed and
  tested on the owner's machine on 2026-11-18: it recovered from a
  reproduced MAC-race failure by itself within about a minute (section 5).
  The old user unit and the separately downloaded daemons are gone.
- The main package, `libero-soc`, does not exist yet. The headless install of
  the vendor software has not been tried.

Next: test-plan.md checklist items 3, 7, 9 and 10 while the current install
still exists (phase 0 is complete, including the backup and the inventory of
files outside `/opt`), then the headless-install check (items 1 and 2), then
phase 1 (uninstall) and round 1 of phase 2.

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
