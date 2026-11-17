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

```
/usr/bin/libero                       wrapper: env vars, exec vendor launcher
/usr/bin/libero-setup                 root tool: install | remove | update | status
/usr/bin/libero-license               root tool: hostid | install <License.dat> | status
/usr/lib/systemd/system/libero-flexlm.service
/usr/lib/systemd/system/libero-flexlm-watchdog.{service,timer}
/usr/lib/sysusers.d/libero-flexlm.conf   system user `flexlm`
/usr/lib/tmpfiles.d/libero-flexlm.conf   /var/lib/libero-flexlm (licence), /var/cache/libero-soc
/usr/lib/udev/rules.d/70-microchip-flashpro.rules
/usr/share/applications/libero-soc.desktop
/usr/share/licenses/libero-soc/        0BSD text for the recipe; pointer to vendor EULA
/usr/share/doc/libero-soc/             short README: setup steps, licence request, opt-ins
```

Vendor tree at `/opt/microchip/Libero_SoC_<ver>`, common dir at
`/opt/microchip/common`, both created by `libero-setup`, root-owned. The
licence file lives at `/var/lib/libero-flexlm/License.dat` (readable by the
`flexlm` user), never inside the vendor tree.

`libero-setup install` **[untested]**: download the web installer to
`/var/cache/libero-soc` (verify checksum when the vendor publishes one;
otherwise record the one observed on first run), show or link the EULA and
require explicit agreement, run the headless install from section 3 with
`Libero_SoC` only, then apply the libstdc++ fix and record what it changed.
`libero-setup remove` calls `maintenancetool purge` and cleans up.
`libero-setup status` reports installed version, free space, licence state.

`libero-license install <file>` **[untested]**: validate that the file's
SERVER hostid matches an interface on this machine, rewrite the SERVER
hostname and the three daemon paths to `<install>/LicenseDaemons/`, copy to
`/var/lib/libero-flexlm/License.dat`, enable and start the unit.
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

One package, `libero-soc` (name subject to the AUR clash check). The licence
service is part of it because the daemons come from the vendor tree and a
Linux user always needs the server. A split into a separate daemon package is
only worth it if someone wants the server on another machine; not planned.

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
- libstdc++ strategy 1, 2 or 3, after the `ldd` sweep.
- Package name: one rolling `libero-soc` versus `libero-soc-<ver>` for
  parallel installs. The vendor layout (`Libero_SoC_<ver>` plus shared
  `common/`) supports parallel installs; the wrapper would then need a
  version switch.
- Watchdog interval and start-gate timeout.
- Whether `libero-setup` also offers SmartHLS as an explicit opt-in flag
  (not installed by default under any circumstances).
