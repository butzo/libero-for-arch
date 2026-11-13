# Handoff: packaging Microchip Libero SoC for Arch Linux

Context document for an AI coding agent. It contains everything learned while
getting Libero SoC 2026.1 running natively on CachyOS (Arch), the owner's
design decisions for turning that into a package (section 1a), and what
remains to be verified (section 9).

Written 2026-11-12 for the repository owner.

Machine-specific and personal values (hostname, user name, MAC addresses,
licence identifiers, serial numbers) are **not** in this file. They live in
`local/machine-private.md`, which must never be committed. Placeholders such
as `<wifi-mac>` below refer to entries in that file.

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
- Section 9 lists what must be verified first. Start there, one item at a time.

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
| Licence server | Part of the same package. **System** unit, dedicated system user (e.g. `flexlm`), daemons taken from `<install>/LicenseDaemons/`. Start gate plus watchdog timer shipped by default. Licence request itself stays manual. |
| Setup runs as | root. `/opt/microchip` root-owned like any package content. |
| Repo licences | 0BSD for the files submitted to the AUR (PKGBUILD, `.SRCINFO`, `.install`); AGPL-3.0-or-later for scripts; CC BY-SA 4.0 for prose. Use `REUSE.toml` to declare per-path. |
| Privacy | `local/` gitignored; see rules in section 0. |
| Disk | The user's filesystem is unknown; do not rely on btrfs compression or any filesystem feature. Peak during setup is roughly download (12.5 GB) plus install (36 GB), i.e. about 13 GB above the final size. |
| Scan-MAC randomisation | Stays enabled by default; disabling it is opt-in documentation only. |

## 2. State of the working machine [verified]

| Item | Value |
|---|---|
| OS | CachyOS (Arch), Hyprland (Wayland); hostname and user in the private file |
| Shell / launcher | zsh / wofi (drun mode) |
| Libero | 2026.1 (build 2026.1.0.17), installed with the web installer |
| Install root | `/opt/microchip/Libero_SoC_2026.1` (owned by the installing user, not root) |
| Common dir (IP vault) | `/opt/microchip/common` (vault at `common/vault`) |
| Launcher script | `.../Libero_SoC/Designer/bin/libero` (shell script) |
| Real binary | `.../Libero_SoC/Designer/bin64/libero_bin` |
| Bundled libs | `.../Libero_SoC/Designer/lib64/rhel/` |
| Icon | `.../Libero_SoC/libero.xpm` |
| FlexLM dir | `/opt/microchip/flexlm` (daemons + `License.dat`) |
| FlexLM version | lmgrd/actlmgrd/snpslmd v11.19.6.0, saltd v11.19.5.0, x64 |
| Licence | Silver 1-year floating, part `LIB-SLV-F-1YR`, port 1702 |
| Licence hostid | `<wifi-mac>` = permanent MAC of `wlan0` (private file) |
| Licence service | systemd **user** unit `flexlm.service`, `lmgrd -z -c ...` |
| Wrapper | `~/.local/bin/libero` (in dotfiles repo, stowed) |
| Other NICs | `tailscale0`, `virbr0`, `vnet*` (libvirt). No wired NIC seen |
| Programmer tested | Embedded FlashPro5, USB `1514:2008` |

Supported OS list per vendor: RHEL/AlmaLinux 8.3 to 8.10 and Ubuntu 22.04.3
only **[doc]**. Arch is unsupported; everything below is a workaround.

## 3. Installer facts

### Correction, 2026-11-12: the 2026.1 installer is Qt Installer Framework

`ls /opt/microchip/Libero_SoC_2026.1/` **[verified]**:

```
components.xml  installer.dat  InstallationLog.txt  installerResources/
Libero_SoC/  LiberoConfig.txt  LicenseDaemons/  SmartHLS/
maintenancetool  maintenancetool.dat  maintenancetool.ini  maintenancetool.sh
network.xml
```

`components.xml`, `network.xml` and `maintenancetool*` are the signature files
of the Qt Installer Framework (IFW) **[inferred from the file set]**.
Consequences:

- Everything below that assumes InstallAnywhere (`-i console`, `-i silent`,
  `-r`/`-f` response files, `IATEMPDIR`, `.com.zerog.registry.xml`) comes from
  documentation for 2023.2 to 2025.x and probably does **not** apply to 2026.1.
  Check `./Libero_SoC_2026.1_online_lin.bin --help` before using any of it.
- IFW (4.x and later) has its own headless CLI **[doc, Qt IFW; untested here]**:

  ```bash
  ./installer --root /opt/microchip/Libero_SoC_2026.1 \
    --accept-licenses --accept-messages --confirm-command --default-answer \
    install [<component ids>]
  ./installer search            # list component ids from the repository
  ./maintenancetool --help      # update / remove / add components later
  QT_QPA_PLATFORM=minimal ...   # if it still wants a display
  ```

  `maintenancetool.ini` shows the IFW version; `components.xml` lists the
  installed component ids and versions.
- `network.xml` holds the repository URLs. An IFW online repository is a set
  of `Updates.xml` files plus `.7z` archives with checksums, so the payload
  may be fetchable per component from stable URLs. That would suit
  `source=()`, but check the EULA before bypassing the installer.
- `maintenancetool` gives a real uninstall and update path, which matters for
  architecture option B (section 8).
- IFW records the target directory in `maintenancetool.dat`/`.ini`. Payload
  relocation is then a matter of vendor scripts, not the installer; the grep
  in section 9 item 5 still decides it.
- **`LicenseDaemons/` exists: the daemons ship with the installer.** The
  separate daemon download is unnecessary for 2026.1. Compare versions with
  `/opt/microchip/flexlm` before relying on it.
- There is no `req_to_install.sh` and no `MegaVault/` in the root. Search the
  tree for a dependency script; `LiberoConfig.txt` and `InstallationLog.txt`
  are unread and worth reading.

### Headless CLI confirmed [verified: `--help` output of the 2026.1 `.bin`]

The installer is Qt IFW 4.10.0 with the generic IFW CLI enabled. Commands:
`install|in <pkg...>`, `check-updates`, `update`, `remove|rm <pkg...>`,
`list`, `search <regexp>`, `create-offline`, `clear-cache`, `purge`.
Relevant options (all marked CLI = headless only):

| Option | Use |
|---|---|
| `-t, --root <dir>` | installation root |
| `--nd, --no-default-installations` | deselect default components (needed to skip SmartHLS) |
| `--am, --accept-messages` / `--da, --default-answer` / `--aa id=value` | answer message boxes |
| `--al, --accept-licenses` | accept EULA; a public package should instead show the EULA and require the user's explicit agreement |
| `-c, --confirm-command` | no confirmation prompt |
| `--ns, --no-size-checking` | skip free-space check (do not use; let it check) |
| `--cp, --cache-path <path>` | metadata cache location; point it at `/var/cache/libero-soc` or similar when running as root |
| `-p, --platform <plugin>` | Qt platform plugin; `-p minimal` or `-p offscreen` if a display is still demanded |
| `--st, --set-temp-repository <URI>` | pin the repository URL from section 3 |
| `-d` (repeatable) | verbosity |
| `<Key=Value>` trailing args | set installer variables, e.g. `CommonDir=/opt/microchip/common` |

The help text notes: "Command ... this feature may be disabled by vendor."
Nothing has been run yet. Candidate setup command **[untested]**:

```bash
./Libero_SoC_2026.1_online_lin.bin \
  --root /opt/microchip/Libero_SoC_2026.1 \
  --cache-path /var/cache/libero-soc/ifw \
  --no-default-installations --accept-messages --confirm-command \
  install Libero_SoC CommonDir=/opt/microchip/common
```

Risks to test: the vendor install script uses custom UI pages
(`licensewidget.ui`, `targetwidgetlibero.ui`, `installationwidgetlibero.ui`)
and may not run without them; vendor variables may be ignored on the command
line; the Linux requirements check (`CHECK_LINUX_REQ_*`) may abort on an
unsupported distro; the "administrator privileges" message box needs an
`--auto-answer` id, which `-d -d` output will reveal.

`maintenancetool` in the install root accepts the same CLI, so `remove`,
`update` and `purge` are the uninstall and update path.

### Installer metadata read on 2026-11-12 [verified]

From `maintenancetool.ini` (Qt settings format, values decoded):

| Key | Value | Meaning for packaging |
|---|---|---|
| `FrameworkVersion` / `IFW_VERSION_STR` | `4.10.0` | Qt IFW confirmed; 4.x has the headless CLI |
| `TargetDir` | `@RELOCATABLE_PATH@` | IFW treats the install as relocatable |
| `CommonDir` | `/opt/microchip/common` | vendor variable, settable |
| `SILENT_INSTALLATION` | `false` | vendor variable: a silent mode exists in their script |
| `MODE_OPTIONS` | `user` | install mode; an admin mode exists too |
| `INSTALLED_AS_ADMIN`, `IS_ADMIN` | `false` | matches the non-root install |
| `supportedOsList` | `windows11,rhel8.10,rhel9,ubuntu22.04.3,ubuntu24.04.3,almalinux8.10,almalinux9` | newer than the list quoted in section 2 |
| `IS_SUPPORTED_OS` | `false` | installer proceeds anyway on CachyOS |
| `HOST_PRODUCT_TYPE` | `cachyos` | read from `/etc/os-release` `ID` |
| `CHECK_LINUX_REQ_STATUS_FILE` / `_CODE` | `check_linux_req_status` / `0` | a Linux requirements check runs; find the script |
| `LINUX_NO_SHORTCUTS` | `false` | variable to suppress desktop-entry creation |
| `CONFIG_JSON` | `:/resource/config.json` | embedded config, lists the vendor variables |
| `PRODUCT_ID`, `CAPTURE`, `JENKINS_BUILD_NO` | `liberosoc`, `2026.1.0.17`, `90` | build identity |
| `RPS_PORT`, `RPS_PORT_M1` | `57606`, `57605` | Remote Programming Service ports |

Vendor variables are passed to an IFW installer as `Key=Value` arguments
**[doc, Qt IFW]**, e.g. `CommonDir=/opt/microchip/common SILENT_INSTALLATION=true`.
Which keys the vendor script honours is **[untested]**.

Repositories (base64 in `DefaultRepositories`, decoded):

- "Akamai Repository":
  `http://ww1.microchip.com/downloads/aemdocuments/documents/fpga-direct/liberosoc/2026.1/90-main/linux`
- "Local Repository": `http://fpgainteg.microsemi.net/...` (vendor-internal,
  ignore)

The public one is plain HTTP on the vendor CDN with the build number (`90`) in
the path, so it looks stable per build **[inferred]**. An IFW repository
serves `<base>/Updates.xml` (component ids, versions, sizes, SHA-1) and
`<base>/<component>/<version><archive>.7z` **[doc, Qt IFW]**. Fetching
`Updates.xml` is the next verification step; it was not reachable from the
session that wrote this file.

#### `Updates.xml` fetched 2026-11-12 [verified, first 80 lines only]

The repository answers without authentication. Header:
`<Checksum>true</Checksum>`, `<MetadataName>2026-07-14-0159_meta.7z</MetadataName>`.

| Component (`Name`) | Archive | Compressed | Uncompressed | Default | Script |
|---|---|---|---|---|---|
| `Libero_SoC` | `libero.soc.7z` | 12.55 GB | 36.18 GB | yes | `installscriptLibero.js` |
| `SmartHLS` | `smarthls.7z` | 0.89 GB | 5.14 GB | yes | `installscriptHls.js` |
| `Program_Debug` | `program.debug.7z` | 0.74 GB | 3.14 GB | no | `installscriptPd.js` |
| `PFSoC_MSS_Configurator` | `pfsoc.mss.configurator.7z` | 0.21 GB | 1.11 GB | no | `installscriptMss.js` |
| `MegaVault` | `megavault.7z` | 4.33 GB | 6.41 GB | no | `installscriptMegavault.js` |
| `RPS` | (cut off) | ? | ? | no | `installscriptRPS.js` |

All at version `2026.1.0.17`. The list was cut at 80 lines; fetch the whole
file for the remaining components. The `Libero_SoC` description says it
already includes Program Debug and the MSS Configurator.

Implications:

- The earlier "20 to 30 GB" size estimate is wrong: Libero alone unpacks to
  36 GB. Measured on the owner's machine (`Libero_SoC` plus SmartHLS, no
  MegaVault): `du -sh` reports 38 GiB for the install root and 898 MiB for
  `common/` **[verified]**. Repackaging in `package()` would have needed about
  85 GB free; that design is rejected (section 1a).
- IFW layout **[doc, Qt IFW; verify with `curl -sI`]**: payload at
  `<base>/<Name>/<Version><archive>` (e.g.
  `<base>/Libero_SoC/2026.1.0.17libero.soc.7z`) with a sibling
  `<archive>.sha1`; the `<SHA1>` in `Updates.xml` belongs to the metadata, not
  the payload. Metadata at `<base>/<MetadataName>` or
  `<base>/<Name>/<Version>meta.7z`.
- The metadata archive is small and contains the `installscript*.js` files.
  They define what the installer does beyond unpacking (variables, post-install
  operations, the Linux requirements check, shortcuts). Read them before
  deciding whether plain extraction of the `.7z` is equivalent to an install.
  They are vendor code: read them, do not commit them.
- SHA-1 only; a PKGBUILD should carry its own `sha256sums` computed after
  download.

`network.xml` has no user repositories; the IFW metadata cache is at
`~/.cache/qt-installer-framework/<uuid>` and may
already contain the repository metadata.

`LicenseDaemons/` contains exactly `lmgrd` (1.5 MB), `actlmgrd` (1.8 MB),
`saltd` (2.7 MB), `snpslmd` (11 MB), dated 2026-09-08. **No** `lmutil`,
`lmhostid` or `lmstat`. `snpslmd` differs in size from the separately
downloaded one (15 MB), so versions differ. A packaged watchdog therefore
cannot rely on `lmstat`; use `pgrep -x actlmgrd` or the journal instead.
Check the versions with `strings <daemon> | grep -m1 'FlexNet Licensing v'`
and confirm the bundled set works with 2026.1 before building on it.

### What the other components are [doc, from `Updates.xml` descriptions]

- **MegaVault**: offline copy of the complete IP core catalogue (6.4 GB).
  Only for machines without internet; otherwise cores download on demand.
- **SmartHLS**: C/C++ high-level synthesis compiler with its own IDE (5.1 GB).
  Not used in a VHDL/Verilog flow. Covered by the Silver licence but excluded
  by the owner's decision.
- **Program_Debug**, **PFSoC_MSS_Configurator**: already contained in
  `Libero_SoC` per its description; listed separately for standalone installs.
- **RPS**: remote programming/debug service. Not needed locally.

### Earlier notes (historical; the InstallAnywhere parts are void for 2026.1)

- The web-installer zip unpacks to two files: `Libero_SoC_2026.1_online_lin.bin`
  (201 MB, ELF 64-bit, InstallAnywhere) and `Libero_SoC_2026.1_online_lin.sh`
  (122 MB, bash script with payload appended). They are independent launchers
  of the same installer **[verified by `file`; independence inferred]**.
- The `.sh` prints `System OS NAME=CachyOS Linux` and exits without installing.
  Cause is assumed to be an OS whitelist on `/etc/os-release` **[inferred]**;
  the script was never grepped.
- The `.bin` fails without `libpng15.so.15` **[verified]**. After installing
  `libpng15` (AUR) it runs in GUI mode **[verified]**.
- It is an *online* installer: it downloads the payload during installation
  **[inferred from name and size]**. Final install is roughly 20 to 30 GB
  **[inferred]**; measure with `du -sh`.
- A separate offline "Full Installer" with published md5/sha256 exists for
  2025.1 and 2025.2 on `microchip.com/Libero` **[doc]**. Whether 2026.1 has one
  is unchecked. If it does, it is the better PKGBUILD source.
- The installer download needs no login; only licence generation is
  account-gated **[verified by the owner]**. Whether the URL is stable or
  session-signed is unknown.
- Without root the installer warns: "You do not have administrator privileges.
  The required drivers and Remote Programming and Debug Services cannot be
  installed." Continuing works **[verified]**.
- The installer writes a desktop entry to
  `~/.local/share/applications/Microchip-Libero_SoC_2026.1.desktop`
  **[verified]**. Expect other writes to `$HOME` (InstallAnywhere registry
  `.com.zerog.registry.xml`) **[inferred]**.
- Environment used for the successful run: `IATEMPDIR=$HOME/tmp/ia`,
  `_JAVA_AWT_WM_NONREPARENTING=1`. Neither was shown to be necessary.

### Silent install, InstallAnywhere era [doc, 2023.2 to 2025.x; does NOT apply to 2026.1]

```bash
<installer> -r /tmp/response_file            # interactive run, records answers
<installer> -i silent -f /tmp/response_file  # replay
<installer> -i console                       # text-mode interactive
```

Documented response-file keys:

```
USER_INPUT_RESULT_1=1
USER_INPUT_RESULT_2=0
USER_INPUT_RESULT_3=0
USER_INSTALL_DIR=<path>
USER_COMMON_DIR=<path>
CHOSEN_FEATURE_LIST=Libero,Synplify,ModelsimPro,Identify,SmartHLS
CHOSEN_INSTALL_FEATURE_LIST=Libero,Synplify,ModelsimPro,Identify,SmartHLS
CHOSEN_INSTALL_SET=Custom
```

Feature names for 2026.1 are unconfirmed. Generate a real response file with
`-r` instead of trusting this list. An earlier note in the owner's reference
doc used `ModelSim` and `CHOSEN_INSTALL_SET=Libero`; those were guesses and are
superseded by the keys above.

### Things to look for in the install root [doc for 2025.1, unchecked for 2026.1]

A BeagleBoard guide shows this layout for 2025.1:
`Libero_SoC_2025.1/{Libero_SoC, LicenseDaemons, MegaVault, SmartHLS, req_to_install.sh}`.

- `req_to_install.sh`: vendor script listing/installing required distro
  packages. Best source for the dependency list.
- `LicenseDaemons/`: if present in 2026.1, the daemons do **not** need a
  separate download. The owner downloaded them separately and believes they
  are not bundled; check the directory before deciding.
- `udev_install` (FlashPro5) and `fp6_env_install` (FlashPro6) scripts
  **[doc]**; location in the 2026.1 tree unknown.

## 4. Runtime fixes that were needed on Arch

Each row is a failure that was hit, in order.

| # | Symptom | Fix applied | Status |
|---|---|---|---|
| 1 | Installer: `libpng15.so.15: cannot open shared object file` | `libpng15` from AUR | [verified] |
| 2 | `libero_bin: libxml2.so.2: cannot open shared object file` | `pacman -S libxml2-legacy` | [verified] |
| 3 | `.../lib64/rhel/libstdc++.so.6: version GLIBCXX_3.4.30 not found (required by /usr/lib64/libicuuc.so.78)` | In `Designer/lib64/rhel/`: rename `libstdc++.so.6` to `.orig`, symlink to `/usr/lib/libstdc++.so.6` | [verified] |
| 4 | `qt.qpa.plugin: Could not find the Qt platform plugin "wayland"` | `QT_QPA_PLATFORM=xcb` (bundled Qt ships xcb only; needs XWayland) | [verified] |
| 5 | Log: `Download Error: error setting certificate verify locations: CAfile: /etc/pki/tls/certs/ca-bundle.crt` | `ln -s /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt` | [verified] |
| 6 | `cat: /etc/redhat-release: No such file` plus "unsupported Alma Linux" warning | cosmetic if left alone; a fake `/etc/redhat-release` removes it and makes fix 3 unnecessary, see below | [verified] |
| 7 | FlexLM: `Can't make directory /usr/tmp/.flexlm` | cosmetic; `ln -s /var/tmp /usr/tmp` silences it (not applied) | [verified] cosmetic, fix [untested] |
| 8 | Programmer visible in `lsusb`, not usable | udev rule with `uaccess`, see section 6 | [verified] |

Cause of 3: the launcher prepends the bundled RHEL library directory to
`LD_LIBRARY_PATH`, so an old bundled libstdc++ gets mixed with newer system
libraries **[inferred, consistent with the error]**. The same conflict may
exist in other tools' private lib directories (Synplify, ModelSim, programmer)
**[inferred]**.

### A fake `redhat-release` replaces fixes 3 and 6 [verified 2026-11-13]

`Designer/bin64/actel_setup_vars_nomotif` is sourced at every tool start. It
runs `cat /etc/redhat-release | grep ...` without checking that the file
exists (the source of the repeated `cat:` errors), prints the "unsupported
Alma Linux" warning as its last fallback, and then builds `LD_LIBRARY_PATH`:
if the file contains `AlmaLinux release 9` (or the host is RHEL 9 or
Ubuntu 24) the bundled `lib64/rhel` directory is left off the path; otherwise
it is prepended, which is what pulls in the old bundled libstdc++.

Test: `/etc/redhat-release` containing `AlmaLinux release 9.6 (Sage Margay)`,
with the original bundled `lib64/rhel/libstdc++.so.6` restored in place of the
symlink. Libero started, place and route completed, no `cat:` lines, no
unsupported-OS warning, no `GLIBCXX` error. Both changes were reverted
afterwards, so the working machine is back to fix 3.

Consequence for the package: provide that one file and leave the vendor tree
unmodified. How to provide it (system file or per-process mount namespace,
section 8) is still open; a real `/etc/redhat-release` may mislead other
software on the host. Not yet tested under the fake file: synthesis,
simulation, programming, and the vendor scripts in `Designer/bin/check_linux_req/`,
which also read the file.

### Dependency list [verified by sweep 2026-11-13]

Method: for every ELF file under `Libero_SoC/` (128,291 files scanned), read
the direct requirements (`objdump -p`, `NEEDED`), drop every name that exists
anywhere in the vendor tree, and map the rest to the owning installed package
with `pacman -Qo`. Result: 91 system libraries from 52 packages, plus 5 names
found nowhere. SmartHLS was not scanned (excluded by decision).

Packages a desktop Arch install is unlikely to have already:

| Package | Needed by | Source |
|---|---|---|
| `libxml2-legacy` | Designer, Synplify, QuestaSim (21 files) | official repos |
| `libxcrypt-compat` | Designer, Synplify, Identify | official repos |
| `gtk2` | Synplify, Identify, a few Designer wx libraries | repo on CachyOS; check plain Arch |
| `ncurses5-compat-libs` | Identify, QuestaSim | repo on CachyOS; check plain Arch |
| `lib32-glibc` | 32-bit ModelSim binaries, a few QuestaSim files | multilib |
| `numactl`, `libtirpc` | QuestaSim | official repos |
| `gperftools` | Synplify, Identify | official repos |
| `pciutils` | Designer | official repos |

The remaining packages are ordinary desktop libraries: `glibc`, `glib2`,
`zlib`, `pango`, `cairo`, `fontconfig`, `freetype2`, `gdk-pixbuf2`,
`at-spi2-core`, `libglvnd`, `libx11`, `libxcb`, `libxext`, `libxrender`,
`libxft`, `libxi`, `libxt`, `libxpm`, `libxtst`, `libxss`, `libxrandr`,
`libxfixes`, `libxdamage`, `libxcomposite`, `libxcursor`, `libxinerama`,
`libxxf86vm`, `libxau`, `libice`, `libsm`, `libxslt`, `libpulse`, `alsa-lib`,
`krb5`, `nss`, `nspr`, `sqlite`, `expat`, `bzip2`, `xz`, `util-linux-libs`,
`systemd-libs`, `graphite`.

Found nowhere, neither in the tree nor on the system:

- `libXm.so.3` (Motif), 2 Designer files. The launcher uses the `_nomotif`
  setup script, so probably unused **[inferred]**.
- `libnsl.so.2` and `libcrdreader.so`, one QuestaSim helper
  (`VisualizerRls/bin/crdapp`).
- Two `libboost_chrono` builds, required only by the bundled `libboost_wave`.

Not direct requirements of anything in the tree, despite earlier guesses:
`libpng12`, `openssl-1.0`, `libjpeg6-turbo`, `libusb-compat`, system Qt 5.
`libpng15` is needed by the installer only. `xorg-xwayland` remains needed at
run time (fix 4). Fonts and locale were not covered by this method.

The earlier `ldd`-based sweep command, for reference. It reports transitive
requirements and, without the launcher's `LD_LIBRARY_PATH`, resolves bundled
libraries to system copies, so it overstates the list (142 packages here):

```bash
find /opt/microchip/Libero_SoC_2026.1 -type f -executable -exec sh -c \
  'ldd "$1" 2>/dev/null | grep "not found"' _ {} \; | sort -u
```

Caveat: `ldd` without the launcher's `LD_LIBRARY_PATH` reports bundled
libraries as missing. Filter out sonames that exist anywhere in the tree.

Place and route and bitstream generation (fabric and sNVM, exported as PPD)
ran clean on 2026-11-12 with 2026.1.0.17 on a PolarFire design: no
missing-library errors, only the cosmetic messages from row 6 **[verified]**.

Not yet exercised at all: simulation (ModelSim/QuestaSim), SmartHLS, actual
programming. Synthesis (Synplify) must have run for place and route to start,
but no log of it was captured **[inferred]**.

## 5. Licensing

### Rules [doc]

- Linux supports floating licences only. Node-locked licences are tied to a
  disk ID and are Windows-only.
- Silver: free, 1 year, renewable. Evaluation: free, 30 days, programming
  disabled. Device coverage per tier is in the licence selector guide.
- Request at microchipDIRECT ("Libero Silver 1Yr Floating License for
  Windows/Linux Server") against a MAC address. Delivered by e-mail.
- 2026.1 needs 64-bit FlexLM v11.19 daemons: `lmgrd`, `actlmgrd` (Libero),
  `snpslmd` (Synplify/Identify), `saltd` (ModelSim/QuestaSim, replaces
  `mgcld`). Download from the Microchip licensing page, "Daemons" tab. Tarball
  name seen in a third-party guide: `Linux_Licensing_Daemon_11.19.6.0_64-bit.tar.gz`.
- The licence is not needed to install, only to run **[verified]**.

### `License.dat` edits [verified working]

Only the hostname on `SERVER` and the daemon paths may change. The hostid may
not: `SIGN=` values depend on it.

```
SERVER localhost <hostid> 1702
DAEMON actlmgrd /opt/microchip/flexlm/actlmgrd
# DAEMON mgcld PATH/mgcld          (leave commented)
DAEMON saltd /opt/microchip/flexlm/saltd
VENDOR snpslmd /opt/microchip/flexlm/snpslmd
```

As delivered: `SERVER <put.hostname.here> ...` and `PATH/actlmgrd`. Remove the
angle brackets. Use absolute paths; relative ones resolve against lmgrd's
working directory. Downloaded daemons may lack the owner execute bit.

A templating step for a package **[untested]**:

```bash
sed -E -e 's|^SERVER +[^ ]+ |SERVER localhost |' \
       -e 's|^((DAEMON\|VENDOR) +[a-z]+ +)PATH/|\1/opt/microchip/flexlm/|' \
       License.dat
```

### Client environment [verified]

```
LM_LICENSE_FILE=1702@localhost
SNPSLMD_LICENSE_FILE=1702@localhost
SALT_LICENSE_FILE=1702@localhost
```

### Current user unit on the owner's machine [verified working; the package uses a system unit instead]

```ini
[Unit]
Description=Microchip FlexLM license server
After=network-online.target

[Service]
ExecStart=/opt/microchip/flexlm/lmgrd -z -c /opt/microchip/flexlm/License.dat
Restart=on-failure

[Install]
WantedBy=default.target
```

`-z` keeps lmgrd in the foreground; logs go to the journal
(`journalctl --user -u flexlm`).

### Healthy-start signature [verified]

```
(lmgrd) Started actlmgrd / saltd / snpslmd
(actlmgrd) HostID node-locked in license file: X
(actlmgrd) HostID of the License Server:       X      <- must be equal
(actlmgrd) Server started on <host> for: ACTEL_BASESOC SmartHLS ...
(saltd)    Server started ... actelmsimvlog actelmsimvhdl Microchipqsim ...
```

`ACTEL_BASESOC` is the Libero feature. `snpslmd` logging "Incompatible vendor
daemon found ... actlmgrd" is benign.

### The MAC race: unsolved, the main reliability problem

Observed **[verified]**:

- NetworkManager randomises the Wi-Fi MAC while scanning. Journal line:
  `device (wlan0): set-hw-addr: set MAC address to <random-mac> (scanning)`.
- A vendor daemon that starts (or is restarted) during a scan reads the random
  MAC, logs `Wrong hostid on SERVER line ... No valid hostids, exiting`, and
  exits with status 34 (`Invalid host`).
- `snpslmd` was restarted by lmgrd 5 s later and recovered. `actlmgrd` was
  **not** restarted and stayed dead for days while lmgrd kept running. Libero
  then shows a "no valid license" popup although Synplify features list fine.
- `systemctl --user restart flexlm` while `wlan0` shows its permanent MAC
  fixes it. `Restart=on-failure` does not help, because lmgrd never exits.

Dummy-interface experiment **[verified failed]**: created
`licmac` (type dummy, MAC `<licmac-mac>`), obtained a new licence for it.
`actlmgrd` still reported the `wlan0` MAC as the server hostid and exited.
Conclusion: vendor daemons use a single interface. That it is the lowest
ifindex / first enumerated is **[inferred]**; Flexera material mentions
`eth0`. The experiment with `wlan0` merely set down was not a valid test of
removing it. The owner reverted to the `wlan0` licence.

Update 2026-11-12 **[verified]**: the active licence is the `wlan0` one
(`SERVER localhost <wifi-mac> 1702`). `licmac` still exists (ifindex 3, MAC
`<licmac-mac>`) but is unused; something recreates it at boot. Interface
order now: `lo`, `wlan0`, `licmac`, `tailscale0`, `virbr0`, `enp0s13f0u3u4`
(USB Ethernet), `enp4s0` (Ethernet). The two Ethernet NICs were absent in
September, so they are probably on a dock **[inferred]** and unsuitable as a
permanent licence anchor.

Resolved 2026-11-13 **[verified]**: FlexLM enumerates every physical NIC and
ignores virtual ones. `lmutil lmhostid` with only `wlan0` physical printed one
host ID; with a USB Ethernet adapter attached it printed two (adapter first,
then `wlan0`) and "Only use ONE from the list of hostids". `licmac` and
`virbr0` were never listed. So the dummy-interface test failed because the
interface was virtual, not because of ordering, and mitigation options 4 and
the dummy approach in general are ruled out.

The vendor daemons accept a licence whose host ID is any entry of that list:
with the adapter attached, `actlmgrd`, `saltd` and `snpslmd` each logged
`HostID of the License Server: "<usb-mac> <wifi-mac>"` against a licence
node-locked to `<wifi-mac>` and started normally. A second NIC appearing or
disappearing therefore does not break a Wi-Fi-anchored licence.

Consequences for `libero-license hostid`: list physical NICs only (those with
`/sys/class/net/<if>/device`), prefer a built-in wired NIC (no scan
randomisation, so no MAC race), offer Wi-Fi as the fallback with the
randomisation warning, and mark USB adapters as removable. On the owner's
machine Wi-Fi is the only permanent NIC, so the start gate and watchdog stay
necessary there.

Mitigation options, none tested. 1 and 2 are decided for the package (section 1a):

1. Start gate: `ExecStartPre` that waits until some interface in
   `/sys/class/net/*/address` equals the SERVER hostid from `License.dat`
   (timeout about 60 s). No `lmutil` is bundled, so read sysfs directly.
   Removes the startup race only, not a mid-run vendor-daemon restart.
2. Watchdog: system timer every few minutes; if `lmgrd` runs but
   `pgrep -x actlmgrd` finds nothing, restart the unit. Covers every case;
   outage bounded by the timer period.
3. Disable scan randomisation for that device only:
   `[device-wlan0] match-device=interface-name:wlan0` plus
   `wifi.scan-rand-mac-address=no`. The owner declined this for privacy
   reasons. Offer as opt-in only.
4. Make the dummy interface enumerate first (create it before the Wi-Fi driver
   loads, e.g. early unit or initramfs). Fragile, order-dependent.
5. Wired NIC or USB Ethernet adapter as the licence anchor, if it enumerates
   before `wlan0`. Subject to the same ordering question as 4.

Decided: 1 and 2 together, 3 documented as opt-in only.

## 6. Programmer (FlashPro) access

- Embedded FlashPro5 enumerates as `1514:2008 Actel Embedded FlashPro5`
  **[verified]**. Default node permissions `crw-rw-r-- root root`: unusable.
- Rule that worked **[verified]**: Libero then found, connected and reserved
  the programmer.

  ```
  # /etc/udev/rules.d/70-microchip-flashpro.rules
  SUBSYSTEM=="usb", ATTRS{idVendor}=="1514", MODE="0660", TAG+="uaccess"
  ```

  `uaccess` grants the logged-in seat user an ACL; no group needed. Vendor
  rules use `GROUP="plugdev"`, which does not exist on Arch.
- Other IDs **[doc]**: `1514:2009` FlashPro6, `1514:200b` embedded FlashPro6
  rev B, `1514:200a` eFP6 rev A (needs firmware upgrade), `0403:6001` FTDI
  FT232 used by older FlashPro hardware.
- FlashPro6 additionally needs `/etc/cyusb.conf` and `88-cyusb.rules`, created
  by `fp6_env_install` **[doc]**. Libero logs "Cannot search for FP6
  programmers. cyusb.conf file not present under /etc folder" **[verified]**;
  harmless without FP6 hardware.
- `ftdi_sio` conflict: the embedded FlashPro5 is a 4-channel FTDI device;
  channel A is JTAG, B to D are UARTs. Vendor kit docs and the ArchWiki
  describe unbinding `ftdi_sio` from interface 0 **[doc]**. On this machine
  the programmer worked with the permissions rule alone; whether `ftdi_sio`
  was loaded was never checked. Treat the unbind rule as possibly needed.
- Open hardware issue, not software: scan chain failed with
  `TDO stuck at 1`. Likely board power, JTAG-select jumper, or the wrong
  target board for the embedded programmer. Not resolved in this session.
- "Remote Programming and Debug Services" were skipped; not needed locally.

## 7. Desktop integration [verified]

Wrapper currently at `~/.local/bin/libero`:

```sh
#!/bin/sh
export QT_QPA_PLATFORM=xcb
export LM_LICENSE_FILE=1702@localhost
export SNPSLMD_LICENSE_FILE=1702@localhost
export SALT_LICENSE_FILE=1702@localhost
exec /opt/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin/libero "$@"
```

Desktop entry:

```ini
[Desktop Entry]
Type=Application
Name=Libero SoC 2026.1
GenericName=FPGA Design Suite
Comment=Microchip Libero SoC design suite
Icon=/opt/microchip/Libero_SoC_2026.1/Libero_SoC/libero.xpm
Exec=libero %f
Terminal=false
Categories=Development;Engineering;
Keywords=libero;soc;fpga;polarfire;mpfs;microchip;vhdl;verilog;synthesis;
StartupNotify=false
StartupWMClass=libero_bin
```

Lessons:

- `Exec=env VAR=... /path/libero` made the entry hard to find in wofi with a
  lowercase query; a lowercase `Exec=libero` wrapper fixed it. The explanation
  (wofi matches on the Exec token) is **[inferred]**.
- Arch does not put `~/.local/bin` on `PATH`. A packaged `/usr/bin/libero`
  avoids the problem.
- Do not export `QT_QPA_PLATFORM=xcb` session-wide; it would push every Qt app
  onto XWayland. Keep it in the wrapper.
- Unverified: `StartupWMClass=libero_bin`, whether `libero <file.prjx>` opens
  a project (`%f`), the path of the FlashPro Express binary.
- The owner's older reference doc (`libero-soc-2026.1-arch.md`) still shows the
  pre-wrapper desktop entry. This section supersedes it.

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

## 9. Verify first (ordered, one at a time)

Done already: install-root listing, `du`, `Updates.xml` fetch, `--help`.

1. `<installer> search` : does headless mode work at all, and which component
   ids does it list? Needs network, installs nothing.
2. Headless install test into a throwaway root, e.g.
   `--root /tmp/libero-test` with `--no-default-installations install Libero_SoC`
   and `-d -d`. Needs about 49 GB free and the download. Record every message
   box id that appears, the exit code, what lands in `$HOME`, and whether
   `CommonDir=` on the command line is honoured. Stop and report if the
   vendor script refuses headless mode; that changes the design.
3. Read `InstallationLog.txt`, `LiberoConfig.txt` and the vendor
   `installscript*.js` from the IFW cache (`~/.cache/qt-installer-framework/`)
   for the post-install steps, the Linux requirements check, and the exact
   desktop-entry and driver actions. Read only; do not commit them.
4. Locate the stable download URL of the web installer and its published
   checksum, if any (`microchip.com/Libero`, "Download Software").
5. Done 2026-11-13, see "Dependency list" in section 4. Remaining: confirm
   on plain Arch which of those packages are in the official repos.
6. Done 2026-11-13 **[verified]**: `lmgrd` from `LicenseDaemons/` started
   with a temp copy of the owner's licence (daemon paths rewritten) and all
   three vendor daemons came up and listed their features, including
   `ACTEL_BASESOC`. All four files are executable as installed. Versions from
   the start-up log: `lmgrd` and `actlmgrd` v11.19.6.0, `saltd` v11.19.5.0,
   `snpslmd` v11.16.4.0 (older than the separately downloaded one). So the
   separate daemon download is not needed. Observed in the same run: every
   daemon logs `Can't make directory /usr/tmp/.flexlm` dozens of times per
   minute, which would flood the journal, so the `/usr/tmp` shim (fix 7) is
   worth applying for the service; and `lmgrd -z` in a terminal did not stop
   on repeated Ctrl-C, so check how the unit stops it. Not yet confirmed:
   that Libero itself checks out a licence from the bundled set.
7. Read `Designer/bin/libero` (how it builds `LD_LIBRARY_PATH`, what it does
   with `/etc/redhat-release`) and `grep -rIl '/opt/microchip'` over the
   tree to learn what `maintenancetool` relocation implies.
8. `paru -Ss libero; paru -Ss microsemi; paru -Ss flashpro` : AUR name clash check.
9. `find /opt/microchip -name '*.rules' -o -name 'udev_install' -o -name 'fp6_env_install'`
10. `lsmod | grep ftdi_sio` with the board attached; is interface 0 bound?
11. Run the rest of one full flow (synthesis with its log captured,
    simulation, programming) to surface missing libraries in the tools that
    have not run yet. P&R and bitstream generation are done, see section 4.

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

## 11. References

- Libero SoC Installation and Licensing Setup User Guide v2026.1 (DS50003561)
- Silent installation: Microchip online docs, section "Performing a Silent
  Installation" of the installation guide
- Libero SoC Linux Environment Setup User Guide (udev_install, fp6_env_install)
- Downloads and checksums: https://www.microchip.com/Libero
- Licensing and daemons: microchip.com, FPGA licensing page, "Daemons" tab
- Licence requests: https://www.microchipdirect.com/fpga-software-products
- PolarFire SoC kit docs (ftdi_sio rules):
  https://github.com/polarfire-soc/polarfire-soc-documentation
- SoftConsole FlashPro troubleshooting (USB IDs):
  https://mi-v-ecosystem.github.io/SoftConsole-Documentation/
- ArchWiki: https://wiki.archlinux.org/title/Libero
