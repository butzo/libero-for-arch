# Design: the libero-soc helper package

How the findings turn into a package, and which decisions are still open.
The decisions already taken by the owner are in section 1a of
[handoff.md](handoff.md) and are not reopened here. The facts this design
rests on are in [findings.md](findings.md).

Section numbers are kept from the time when all of this was one file:
sections 2 to 7 and 11 are in findings.md, section 9 is in
[test-plan.md](test-plan.md).

## 8. Packaging design

Three sub-problems: (a) distro shims, (b) the large vendor install,
(c) the licence service. The architecture is decided (section 1a): a helper
package whose setup tool drives the vendor web installer headlessly.
Rejected alternatives, for the record: repackaging the vendor tree in
`package()` (about 85 GB peak, 36 GB package, network inside `package()`),
and a distrobox container (second OS userland, weak host integration).

### Package contents (target)

Two packages since 2026-11-17 (section 1a). `libero-soc`, in `soc/` and
`aur/libero-soc/` (written 2026-11-18):

```
/usr/bin/libero                       wrapper: env vars, pseudo-terminal (section 4), vendor launcher
/usr/bin/libero-setup                 root tool: install | remove | status
/usr/lib/tmpfiles.d/libero-soc.conf   /var/lib, /var/cache and /var/log/libero-soc
/usr/lib/udev/rules.d/70-libero-soc.rules   vendor 1514, uaccess
/usr/share/applications/libero-soc.desktop  icon from /var/lib/libero-soc/libero.xpm
/usr/share/doc/libero-soc/README.md
/etc/redhat-release                   shim, "AlmaLinux release 9.6"
/etc/pki/tls/certs/ca-bundle.crt      shim, link to /etc/ssl/certs/ca-certificates.crt
```

There is no `update` command: a new Libero version is `remove`, then
`install` with the new installer.

`libero-flexlm`, the licence server, in `flexlm/` and `aur/libero-flexlm/`:

```
/usr/bin/libero-license               hostid | install <License.dat> | status (+ wait-hostid, watchdog for the units)
/usr/lib/systemd/system/libero-flexlm.service            lmgrd behind the start gate
/usr/lib/systemd/system/libero-flexlm-watchdog.{service,timer}   every minute
/usr/lib/systemd/system/libero-flexlm-resume.service     restart after resume
/usr/lib/sysusers.d/libero-flexlm.conf   system user `libero-flexlm`
/usr/lib/tmpfiles.d/libero-flexlm.conf   /var/lib/libero-flexlm
/usr/tmp -> ../var/tmp                   FlexLM lock files (fix 7 of section 4)
/usr/share/doc/libero-flexlm/README.md
```

Vendor tree at `/opt/microchip/Libero_SoC_<ver>`, common dir at
`/opt/microchip/common`, both created by `libero-setup`, root-owned. The
licence file lives at `/var/lib/libero-flexlm/License.dat` (readable by the
`libero-flexlm` user), never inside the vendor tree. The daemons stay in the
vendor tree and are reached through the link `/var/lib/libero-flexlm/daemons`,
so a Libero update needs one link changed and no licence edit.

`libero-setup install` **[untested]**: download the web installer to
`/var/cache/libero-soc` (verify checksum when the vendor publishes one;
otherwise record the one observed on first run), show or link the EULA and
require explicit agreement, run the headless install from section 3 with
`Libero_SoC` only, then apply the libstdc++ fix and record what it changed.
`libero-setup remove` calls `maintenancetool purge` and cleans up.
`libero-setup status` reports installed version, free space, licence state.

Consequences of the installer scripts (findings.md section 3, 2026-11-18):

- Run as root, the installer is in admin mode. Pass the target and common dir
  explicitly (`--root /opt/microchip/Libero_SoC_<ver>`,
  `CommonDir=/opt/microchip/common`), pass `LINUX_NO_SHORTCUTS=true` so that
  no menu entries or icons go system-wide or onto root's desktop (the package
  ships its own), select `Libero_SoC` with `--no-default-installations`
  (SmartHLS is a default component), and never select RPS.
- Admin mode runs `fp6_env_install`, which gives every Microchip USB device
  mode 666 through `/etc/udev/rules.d/88-cyusb.rules` and writes
  `/etc/cyusb.conf`, outside pacman's knowledge. `libero-setup install` must
  replace that rule with the package's `uaccess` rule afterwards. Decided
  2026-11-18: `/etc/cyusb.conf` stays the vendor's file, not the package's.
  FlashPro6 users need it; the name is generic enough to clash with other
  Cypress tools; and the vendor script writes to it on every install anyway.
  `libero-setup remove` deletes its FlashPro6 line, and the file when nothing
  else is listed.
- Temporary space: point `TMPDIR` and `--cache-path` at
  `/var/cache/libero-soc` on disk. A RAM-backed `/tmp` cannot hold the
  12.5 GB download (7.6 GB on the owner's machine).
- No fake `/etc/redhat-release` may exist while the installer runs, or the
  requirements check runs `yum` as root. Apply the shims after the install,
  or keep them inside the wrapper's namespace (shim option 2).
- In CLI mode the installer rejects every prompt, so the target directory
  must be empty or absent.
- Uninstall: `maintenancetool purge` as root. Verified 2026-11-18 on the
  test install: it removes the whole target tree in seconds and leaves the
  empty common dir behind. `libero-setup remove` then removes the common dir
  if empty, plus the `fp6_env_install` files, which the purge leaves in
  `/etc`.
- `/usr/bin/libero` must call `<install>/Libero_SoC/Designer/bin/libero` by
  its full path; a symlink to it breaks the vendor launcher.

Confirmed by the headless install of 2026-11-18 (findings.md section 3); the
command recorded there is the basis for `libero-setup install`. Open points
it raised:

- **EULA.** CLI mode skips the vendor's licence page, so `libero-setup` has to
  show the agreement itself and ask for consent before it passes
  `--accept-licenses`. Decided 2026-11-18: the agreement is embedded in the
  web installer as a plain-text Qt resource (a 4-byte big-endian length, then
  the text). `libero-setup` cuts it out byte-exact (2026.1: 69,981 bytes,
  "License Rev. No. 10-121225"), shows it in a pager and requires typing
  `I accept`; `--accept-eula` is the non-interactive equivalent. Text and
  consent record go to `/var/lib/libero-soc/`. The agreement's own wording
  asks for an explicit "I accept"; a bare yes/no without the text would not
  match it **[inferred, not legal advice]**. The agreement forbids
  unauthorised modification and distribution; the package does neither.
- **Icon.** With `LINUX_NO_SHORTCUTS=true` the tree has no Libero icon.
  Decided 2026-11-18: `libero-setup` cuts `libero.xpm` out of the installer
  the same way (byte-identical to the file the GUI install creates) into
  `/var/lib/libero-soc/libero.xpm`, where the package's desktop entry points.
  The package itself ships no vendor artwork.
- **Download per install.** The IFW cache is deleted on exit, so updates and
  reinstalls download 12.5 GB again. Acceptable; `create-offline` remains
  untested.
- **Shims after install.** The fake `/etc/redhat-release` had to be moved
  aside for the install and restored afterwards; the package must order it
  the same way or use shim option 2.
- **IP vault.** With a root-owned common dir, Libero falls back to a per-user
  vault in `~/.actel/vault` without complaint (findings.md section 3). That
  needs no writable system directory, at the cost of one copy of the cores
  per user. Decided 2026-11-18: keep the common dir root-owned and rely on
  the fallback; a shared, group-writable vault is an opt-in at most, not
  built. `libero-setup remove --purge` lists `~/.actel/vault` among the
  per-user data it cannot remove.
- **libstdc++.** Not needed: the pristine tree runs with the fake
  `redhat-release` alone (libstdc++ option "none").

`libero-license install <file>` (written, covered by
`tests/libero-license.test.sh`): validate that the file's SERVER hostid
matches a physical interface on this machine, rewrite the SERVER hostname and
the daemon paths (through the daemons link), copy to
`/var/lib/libero-flexlm/License.dat`, enable and start the units.
`libero-license hostid` prints the candidate MACs with a warning about
randomised Wi-Fi MACs and virtual interfaces.

`post_install` message: run `libero-setup install`, request a Silver floating
licence for the MAC shown by `libero-license hostid`, then
`libero-license install`.

### Shim strategy options

1. System-wide files owned by the package: the `/etc/pki/tls/certs/ca-bundle.crt`
   symlink and `/usr/tmp`. Simple; check for conflicts with `pacman -Qo` / `pacman -F`.
2. Per-process mount namespace in the wrapper **[untested]**: no host changes.

   ```sh
   exec bwrap --dev-bind / / \
     --ro-bind /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
     --ro-bind /usr/share/libero-soc/redhat-release /etc/redhat-release \
     --bind /var/tmp /usr/tmp \
     /opt/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin/libero "$@"
   ```

   Bind targets must exist or be creatable; with `/` bound read-write this
   needs care (use `--tmpfs` parents or pre-created empty files). A fake
   `redhat-release` may also change which bundled lib directory the launcher
   selects, so test with and without it.

libstdc++ strategy options:

1. Replace the bundled file with a symlink (what works today). Modifies the
   vendor tree; repeat per tool directory as needed.
2. `LD_PRELOAD=/usr/lib/libstdc++.so.6` in the wrapper **[untested]**. Leaves
   the tree untouched but is inherited by every child tool.
3. Drop `libxml2-legacy` and instead supply an old `libxml2.so.2` that does not
   pull in system ICU **[untested]**. Removes the cause instead of the symptom.

### Package split

Two packages (owner's decision, 2026-11-17): `libero-soc` for the software
itself and `libero-flexlm` for the licence server. Names are subject to the
AUR clash check. Decided by the owner 2026-11-22: `libero-flexlm` is an
optional dependency of `libero-soc`, because users with an organisation
licence server do not need it. They set `LM_LICENSE_FILE`,
`SNPSLMD_LICENSE_FILE` and `SALT_LICENSE_SERVER`; the wrapper keeps values
already set. `libero-setup` names `libero-license` only when it is installed.

### Legal and AUR notes [inferred, not legal advice]

- The PKGBUILD is the packager's own text; the AUR hosts no binaries. Use the
  vendor URL in `source=()` if it is stable, otherwise the manual drop-in
  pattern (`local://` source with instructions).
- Read the Libero EULA for clauses on automated download and on modifying the
  installed tree (the libstdc++ symlink is a modification made on the end
  user's machine).
- Checksums for full installers are published on `microchip.com/Libero`; use
  them for `sha256sums`.
- A web search found no existing AUR package for Libero. Not checked against
  the AUR directly; do so before choosing a name.
- ArchWiki page: `https://wiki.archlinux.org/title/Libero` ("Microsemi
  Libero"). It covers udev rules and the kernel-module conflict and describes
  much older versions. It is behind an anti-bot wall; read it in a browser.

### Public repository and licence [not legal advice]

The owner plans a public repo documenting this work, preferably AGPL.

- His own text and scripts can carry any licence. AGPL-3.0 applies cleanly to
  scripts; its network clause has no practical effect on a PKGBUILD or docs.
  Options: AGPL-3.0-or-later for everything; AGPL for scripts plus
  CC BY-SA 4.0 for prose; 0BSD for the files that go to the AUR.
- AUR: adding a `LICENSE` and/or `REUSE.toml` is expected; 0BSD is encouraged,
  not required. Another licence does not bar AUR submission, only promotion to
  the official repositories (irrelevant for proprietary software) **[doc]**.
- ArchWiki contributions are published under the GFDL. The author may
  contribute his own text there regardless of the repo licence.
- `license=()` in the PKGBUILD describes Libero itself (proprietary, a
  `LicenseRef-` entry), not the repo.
- Never commit: vendor archives or binaries, `License.dat` or any `SIGN=`
  value, MAC addresses/hostids, vendor `installscript*.js`, verbatim vendor
  documentation, the installer metadata archive, anything under `local/`.
- Parts of the documentation were drafted by an AI assistant. Copyright in
  AI-generated text is unsettled in several jurisdictions, so copyleft may not
  be enforceable on those passages. Rewriting them in the owner's words avoids
  the question.

## 10. Decisions left to the agent

Decide these from test results and record the reasoning in the repo. Ask the
owner only if a test result makes a section 1a decision impossible.

- Shim strategy: package-owned system files or per-process namespace.
  Decided 2026-11-18: package-owned files, `/etc/redhat-release` and the
  link `/etc/pki/tls/certs/ca-bundle.crt`. A per-process namespace needs the
  bind target to exist on the host, and an unprivileged user cannot create
  `/etc/redhat-release` there. `libero-setup install` moves the file aside
  while the vendor installer runs.
- libstdc++ strategy 1, 2 or 3, after the `ldd` sweep. Decided 2026-11-18:
  none of them; the fake `redhat-release` makes the vendor launcher leave the
  bundled libstdc++ off the library path, verified on a pristine tree.
- Package name: one rolling `libero-soc` versus `libero-soc-<ver>` for
  parallel installs. The vendor layout (`Libero_SoC_<ver>` plus shared
  `common/`) supports parallel installs; the wrapper would then need a
  version switch. Decided by the owner 2026-11-18 (handoff.md section 1a):
  one package, one version at a time for now, side-by-side installs later.
- Watchdog interval and start-gate timeout. Decided 2026-11-17 in
  `libero-flexlm`: check every minute, restart at most every three minutes,
  not within 60 s of a (re)start and not while lmgrd waits for its port; the
  start gate waits without a timeout and lets systemd retry every 30 s on
  errors.
- Whether `libero-setup` also offers SmartHLS as an explicit opt-in flag
  (not installed by default under any circumstances).
