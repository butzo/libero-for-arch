# Findings: Libero SoC 2026.1 on Arch Linux

What has been learned about installing and running Libero SoC 2026.1 on
CachyOS (Arch): the installer, the fixes needed at run time, licensing, the
programmer and desktop integration.

Every claim carries a confidence tag (**[verified]**, **[doc]**,
**[inferred]**, **[untested]**). The tags and the rules for working in this
repository are defined in [handoff.md](handoff.md). The package design is in
[design.md](design.md), the list of what is still to be verified in
[test-plan.md](test-plan.md).

Section numbers are kept from the time when all of this was one file:
sections 0, 1 and 1a are in handoff.md, 8 and 10 in design.md, 9 in
test-plan.md.

Machine-specific and personal values are not in this file. Placeholders such
as `<wifi-mac>` refer to entries in `local/machine-private.md`.

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

### What the installer scripts do [verified 2026-11-18]

Sources, read only and not committed: `InstallationLog.txt`; the component
metadata archive from the public repository (its SHA-1 matched
`Updates.xml`); the controller script inside `maintenancetool.dat`; and the
helper script compiled into the web installer `.bin`.

Work beyond unpacking, per component:

- Creates the common dir and writes `LiberoConfig.txt` there with mode 666.
  Appends the release to `Designer/adm/verinfo` and sets about nine values in
  `Designer/data/install.def` (see "Hard-coded install paths" below).
- Copies `lmgrd`, `actlmgrd`, `snpslmd` and `saltd` from `Designer/bin64`
  into `LicenseDaemons/`.
- Writes icons, `.desktop` and `.directory` files into the tree, then
  registers them with `xdg-desktop-menu` and `xdg-desktop-icon` (the source
  of the menu files and home-directory copies listed under "Files outside
  `/opt`").
- Runs `chmod -R 755` over the target directory, and runs the Linux
  requirements check.
- Only when it has admin rights: runs `Designer/bin/fp6_env_install`
  (section 6), and offers the RPS component, which installs a systemd service
  (`prgsrvdmn`) and opens ports 57605 and 57606 in firewalld or ufw.

**Admin mode** means the installer runs with admin rights, i.e. as root.
It then registers the menu entries system-wide, while `xdg-desktop-icon`
has no system mode and would put icons on root's desktop **[inferred]**. Its
default target becomes `/usr/local/microchip/` (user mode: `~/microchip/`).
It runs `fp6_env_install`, offers RPS, and records the install as admin, after
which uninstalling requires root.

**Linux requirements check** (`Designer/bin/check_linux_req/`): recognises
SUSE, Ubuntu, AlmaLinux and RHEL from `/etc/os-release`, `/etc/issue` and
`/etc/redhat-release`; on anything else it reports "not supported" (status 44
on this machine). It only warns and never aborts the install. As root the
distribution-specific scripts change the system: the AlmaLinux and RHEL
variants run `yum`, the Ubuntu variant edits `sources.list`. With a fake
`/etc/redhat-release` present during a root install it would therefore try to
run `yum` **[inferred]**, which does not exist on Arch.

**Variables.** Kept when given on the command line: `TargetDir`,
`CommonDir`, `LINUX_NO_SHORTCUTS`, `RPS_PORT`, `CONFIG_JSON`. Always set by
the scripts: `SILENT_INSTALLATION` (true in CLI mode), `IS_ADMIN`,
`MODE_OPTIONS`. In CLI mode every component script auto-rejects message
boxes. The vendor's own message boxes have no ids, so `--auto-answer` cannot
target them; none of them appears in an install as root.

**Headless.** Nothing blocks CLI mode explicitly. The custom pages (licence,
target, installation, RPS port), the component choice, the disk-space check
and the uninstaller's removal of the target directory live in GUI page
callbacks, so they do not run in CLI mode. Commented-out automation calls
suggest the vendor tried and gave up. `Libero_SoC` and `SmartHLS` are default
components.

**The `.sh` launcher** of the web installer maps `--root` to `TargetDir` and
`--no-shortcuts` to `LINUX_NO_SHORTCUTS=true`, puts the IFW cache under
`$TMPDIR`, and refuses several CLI commands (remove, update, list, search
and others). The `.bin` is the IFW binary itself with the generic CLI.

### Headless install as root works [verified 2026-11-18]

Command, run by the owner as root, with the vendor's `.bin` (IFW CLI), the
fake `/etc/redhat-release` moved aside, and a target that did not exist yet:

```sh
sudo env TMPDIR=/var/tmp/libero-ifw <installer>.bin -p minimal -d -d \
  --root /opt/microchip-test/Libero_SoC_2026.1 \
  --cache-path /var/tmp/libero-ifw/cache \
  --set-temp-repository http://ww1.microchip.com/downloads/aemdocuments/documents/fpga-direct/liberosoc/2026.1/90-main/linux \
  --no-default-installations --accept-licenses --accept-messages --confirm-command \
  install Libero_SoC CommonDir=/opt/microchip-test/common LINUX_NO_SHORTCUTS=true
```

- **Result:** exit 0, "Components installed successfully". 7.3 min download
  (12.5 GB), 5 min unpack, 12 min in total. No prompt appeared.
- **Mode:** the log shows `IS_ADMIN: true`, `MODE_OPTIONS: system`, and
  "installing with administrator privileges".
- **Components:** only `Libero_SoC`, with Synplify Pro, Identify, ModelSim ME
  Pro and QuestaSim ME inside it. No SmartHLS, MegaVault or RPS. 34 GB
  installed; the installer's own estimate was 33.76 GB plus 11.69 GB of
  temporary space, and it checked free space before downloading.
- **Repository:** `--set-temp-repository` replaced the default repositories,
  so the 40 s timeout on the vendor-internal host did not occur.
- **Licence page:** the log says "Headless installation: skip wizard page
  addition: LicenseWidget"; the same happens to the target and installation
  pages. The vendor's EULA is therefore never shown in CLI mode. Whether
  `--accept-licenses` was needed at all is unknown.
- **Paths:** `--root` and `CommonDir=` were honoured. `install.def` holds
  eight absolute paths into the target, and `VAULT_LOCATION` points to
  `<common>/vault`. `ACTCMN_DIR` stays relative.
- **Tree:** all files root-owned, mode 755 (`chmod -R 755`). Compared file by
  file with the owner's GUI install of the same build, the trees match except
  for the installer's bookkeeping files, `install.def` (paths), Python
  `__pycache__` files created at run time in the owner's tree, and the nine
  icon, `.desktop` and `.directory` files, which `LINUX_NO_SHORTCUTS=true`
  suppresses. The tree then contains **no Libero icon** at all.
- **Outside the tree:** no menu entries anywhere (`/usr/share/applications`,
  `/usr/local`, `/etc/xdg` unchanged). `fp6_env_install` ran and created
  `/etc/cyusb.conf` and `/etc/udev/rules.d/88-cyusb.rules`: every USB device of
  vendor 1514 gets mode 666, with `TAG="cyusb_dev"`. udev's `=` on a list key
  replaces earlier values **[doc]**, so the rule probably drops the `uaccess`
  tag set by an earlier rule **[inferred]**.
- **Requirements check:** "Linux OS flavor not supported", status 44, only
  logged; plus two harmless `grep: stray \` warnings from the vendor script.
- **Temporary space:** nothing of the download remained in
  `/var/tmp/libero-ifw` afterwards, apart from an empty `remoterepo-*`
  folder. The cache folder given with `--cache-path` is deleted on exit (also
  seen with `search`), so every install downloads the 12.5 GB again.

`search` as a normal user, with a throwaway home, also worked and listed six
components: `Libero_SoC`, `SmartHLS`, `Program_Debug`,
`PFSoC_MSS_Configurator`, `MegaVault`, `RPS`. It wrote nothing into the home
directory. As a normal user the non-admin warning box was answered "Cancel";
`search` continued regardless, but an `install` as a normal user might stop
there **[untested]**.

Root's home directory was checked afterwards with `find -newer` against a
marker file: the root install wrote nothing there **[verified]**.

### Libero run from the root-owned test install [verified 2026-11-18]

The test install above, unmodified (no libstdc++ fix in its `lib64/rhel`),
started as the owner's normal user inside a pseudo-terminal, with the fake
`/etc/redhat-release` in place and the licence from the `libero-flexlm`
service. Project: a copy of the owner's GNSS project with its four tool paths
pointed at the test tree.

- **Flow:** reported by the owner: no licence popup, synthesis, place and
  route, bitstream generation and pre-synthesis simulation (ModelSim GUI)
  all worked. Terminal output contained nothing but the known ini notes.
  So the fake `redhat-release` alone is enough on a pristine tree; the
  libstdc++ change is not needed.
- **IP vault:** the configured vault, `<common>/vault`, did not exist and
  could not be created by the user (common dir root-owned, mode 755). Libero
  did not complain: two seconds after start it created a per-user vault in
  `~/.actel/vault` and downloaded the cores the project needed there (436
  files, 249 MB). The vault in the common dir stayed empty.
- **Also written:** `~/.config/Actel/Default.conf` (window geometry).
- **Programmer:** not yet checked against this tree.

### Hard-coded install paths [verified 2026-11-18]

- **Launchers.** `Designer/bin/libero` runs `../bin64/<its own name>` relative
  to `dirname $0`, without resolving symlinks. `bin64/libero` resolves one
  level of symlink by parsing `ls -ld`, which breaks on relative targets,
  then sources `actel_setup_vars_nomotif` unless `ACTEL_SKIP_VAR_SETUP` is
  set. A packaged `/usr/bin/libero` must therefore call the launcher by its
  full path, not be a symlink to it.
- **Text files containing `/opt/microchip`:** nine. `LiberoConfig.txt`;
  `Designer/data/install.def`, which holds the install location, the IP vault
  (`<common>/vault`), the ModelSim, QuestaSim, Synplify and Identify locations
  and Questa library defaults; and the seven `.desktop` and `.directory`
  files. `maintenancetool.ini` also stores the common dir (UTF-16 encoded);
  its target dir is stored as relocatable.
- **Binaries:** no ELF file checked (`libero_bin`, `sdebug_bin`, `synbatch`,
  both `vsim`, `libcyusb.so`) contains the path.

All of these are written at install time from `TargetDir` and `CommonDir`,
none is a build-time constant. Any target can be chosen at install time;
moving an installed tree means rewriting `install.def`, the entries and
`maintenancetool.ini`.

### Files outside `/opt` [verified 2026-11-18]

Inventory on the owner's machine after the 2026.1 web install as a normal
user, two months of use, and the `libero-flexlm` package. Found by name
(Actel, Microsemi, Microchip, Libero, ModelSim, Synplify and similar) in the
home directory to depth 4, by content in `/etc`, and by checking each path
with `pacman -Qo`. Root's home was not checked; the install ran as the user.
This is the checklist for phase 1 and for `libero-setup remove`.

Written by the vendor installer:

| Path | Content |
|---|---|
| `~/.local/share/applications/Microchip-{Libero_SoC,FPExpress,PFSoC_MSS_Configurator,Program_Debug,SmartHLS}_2026.1.desktop` | Menu entries, one per tool, including SmartHLS |
| `~/Microchip-*_2026.1.desktop` (the same five) | Copies directly in the home directory |
| `~/.local/share/desktop-directories/Microchip-Microchip.directory`, `~/.config/menus/applications-merged/user-Microchip-Microchip.menu` | "Microchip" submenu |
| `~/.cache/qt-installer-framework/` | Installer cache, empty |

Written by the tools at run time (user settings and caches):

| Path | Content |
|---|---|
| `~/.actel/` (14 MB) | `libero.def`, `flashpro.def`, `dsma.ini`, `PlannerColorSettings.ini`, `UserPresets/`, `template/`, and `repository_cache/` (13.9 MB, IP catalogue cache) |
| `~/.actel.<hostname>` | Empty file |
| `~/.config/Actel/` | `Libero.conf`, `libero.2026.1.0.17.conf`, `FlashPro Express.conf`, `SmartDebug.conf`, `PolarFireSoC MSS Configurator.conf` |
| `~/.config/Microsemi/` | I/O Editor settings |
| `~/.modelsim`, `~/.modelsim.bak` | ModelSim GUI preferences, written by `vish` |

Arch fixes made by hand (sections 4 to 7):

| Path | Owner | Replaced in the package by |
|---|---|---|
| `/etc/redhat-release` | none | the shim chosen in section 8 |
| `/etc/pki/tls/certs/ca-bundle.crt` (link) and `/etc/pki/tls/` | none (`/etc/pki` itself belongs to `fwupd`) | the shim chosen in section 8 |
| `/etc/udev/rules.d/70-microchip-flashpro.rules` | none | `/usr/lib/udev/rules.d/` in `libero-soc` |
| `~/.local/bin/libero`, `~/.local/share/applications/Microchip-Libero_SoC_2026.1.desktop` | dotfiles (the entry replaces the installer's) | `/usr/bin/libero`, `/usr/share/applications/` in `libero-soc` |

Packages installed explicitly for Libero on 2026-09-08, required by nothing
else: `libpng15` (AUR, installer only), `libxml2-legacy`,
`ncurses5-compat-libs`. The other dependencies of section 4 (`gtk2`,
`libxcrypt-compat`, the `lib32-*` set, `numactl`, `libtirpc`, `gperftools`,
`pciutils`) are present on this machine because other software needs them.

Leftovers from earlier versions and experiments, not part of a normal
install: eight menu entries for 2025.2 whose target `~/microchip/` no longer
exists, an empty `~/distrobox/libero`, and the downloaded web installer in
`~/tmp/` (zip and extracted copy, about 520 MB).

Not found: `~/.flexlmrc`, `/etc/cyusb.conf`, FlexLM lock directories outside
the licence service's private `/tmp`, anything in `/usr/local`, other files in
`/etc` that mention Libero or Microchip.

Consequences for `libero-setup remove`: the installer's files are removed
always; the run-time settings and caches only with `--purge`, because they
are user data. They live in every user's home, so the root tool can only list
them or act for the user who runs it. The installer writes its menu entries
for the installing user; when the setup tool installs as root they would land
in root's home, which round 1 has to check.

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
software on the host. Synthesis also passed under the fake file (same day).
Not yet tested under it: simulation, programming, and the vendor scripts in
`Designer/bin/check_linux_req/`, which also read the file.

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
| `lib32-glibc`, `lib32-gcc-libs`, `lib32-libx11`, `lib32-libxext`, `lib32-libxrender`, `lib32-libxft`, `lib32-fontconfig` | ModelSim, whose programs (`vsim`, `vish`, `vsimk`, compilers) are 32-bit | multilib |
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

Synthesis ran clean on 2026-11-13 under the fake `redhat-release` setup
(Synplify Pro Y-2026.03M, licence `synplifypro_actel` checked out from the
local server, exit status 0, no library errors) **[verified]**.

ModelSim (2025.3, 32-bit) starts and its GUI opens when run directly with
`SALT_LICENSE_SERVER` set, 2026-11-14 **[verified]**.

Pre-synthesis simulation started from the Libero GUI works, 2026-11-16 and
2026-11-17 **[verified]**: on a PolarFire SoC project of the owner with a
VHDL testbench and the CoreUART and CoreAPB3 libraries, Libero generated
`run.do`, ModelSim Pro 2025.3 compiled everything with 0 errors, loaded the
design and the PolarFire PLI library, opened its GUI with the waveforms, and
`run -all` ended with the testbench's own pass message. Confirmed for three
ways of starting Libero: from a terminal, through the wrapper, and from the
desktop entry. The last two needed the pseudo-terminal fix below.

### ModelSim needs a terminal on Libero's standard input [verified 2026-11-17]

Symptom: "Simulate" shows "Starting Simulation..." and no window appears.
The simulation log shows a clean compile and load, then
`wave ... not supported in batch mode`, `# <EOF>` and an exit with 0 errors.

Cause: `vsim` inherits Libero's standard input and chooses its mode from it
(the binary calls `isatty`). With a terminal it opens the GUI. Without one
it runs in batch mode, reads end-of-file and quits. Libero has no terminal
on standard input when it is started from a desktop entry, or from a wrapper
that redirects it from `/dev/null`. Started by hand in a terminal it works,
which hid the problem at first.

Fix: start Libero inside a pseudo-terminal. `script` from util-linux (part
of the base system) does that:

```sh
script -qc '<install>/Libero_SoC/Designer/bin/libero' /dev/null
```

Details that matter for the package wrapper and desktop entry (section 7):

- `script` hands its command to `$SHELL` as one string. Arguments such as a
  project path have to be shell-quoted, and `SHELL=/bin/sh` should be set for
  the `script` call so the quoting does not depend on the user's shell.
- Inside the pseudo-terminal the vendor launcher stays in the foreground
  until Libero exits (the `script` session lasted exactly as long as Libero),
  so the pseudo-terminal lives as long as needed without extra waiting code.
  This differs from the start without a terminal, see the side finding in
  section 9 item 6.
- `script` itself runs fine with `/dev/null` on its own standard input, so
  `setsid -f script ... </dev/null >/dev/null 2>&1` detaches cleanly.

One error remains in the transcript and is cosmetic: `invalid command name ""`
from the line `TreeUpdate [SetDefaultTree]` of a saved wave file. The
waveforms are shown regardless. Whether it also appears on a supported
distribution was not checked.

Programming a device with the embedded FlashPro5 worked, reported by the
owner 2026-11-16 **[verified]**. Which shim setup was active was not
recorded.

Correction, 2026-11-16: the working machine is on the fake
`/etc/redhat-release` (AlmaLinux 9.6) with the original bundled
`lib64/rhel/libstdc++.so.6` in place, not on the libstdc++ symlink
**[verified]**. The statement above that both changes were reverted on
2026-11-13 no longer describes the machine. The simulation results, and
probably the programming run **[inferred]**, are therefore results under the
fake file.

Not yet exercised at all: QuestaSim, SmartHLS, post-synthesis and post-layout
simulation.

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
SALT_LICENSE_SERVER=1702@localhost
```

Corrected 2026-11-14: the simulator variable is `SALT_LICENSE_SERVER`, not
`SALT_LICENSE_FILE`. The bundled ModelSim (2025.3) ignores the old names;
its release notes say `MGLS_LICENSE_FILE` and `LM_LICENSE_FILE` are deprecated
since 2025.1 in favour of `SALT_LICENSE_SERVER` **[doc]**. Without it `vsim
-gui` exits with status 4 and "license file environment variable
(SALT_LICENSE_SERVER) is not set correctly"; with it the GUI opens
**[verified]**. Started from Libero, a failing simulator shows nothing but
"Starting Simulation..." in the log window.

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

### The MAC race: the main reliability problem, handled by `libero-flexlm`

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
- Trigger identified 2026-11-13 **[verified from the journal]**: wake from
  sleep. After a 34-minute suspend all three vendor daemons logged "Lost
  connection to lmgrd, heartbeat timeout expired" and exited; lmgrd restarted
  them within three seconds; `saltd` and `actlmgrd` read the wrong MAC and
  exited with status 34; NetworkManager logged `set-hw-addr: reset MAC address
  ... (preserve)` three seconds after that. So on a Wi-Fi-anchored laptop
  this is likely on every resume, not a rare race. While in that state
  `systemctl start` is a no-op (the unit is still active) and both Libero and
  the simulator fail to check out.

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
randomisation warning, and mark USB adapters and dock NICs as removable. On
the owner's machine Wi-Fi is the only permanent NIC, so the start gate and
watchdog stay necessary there.

Mitigation options as considered before the package existed. 1, 2 and 6 are
implemented in `libero-flexlm` and tested, see the next subsection:

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

6. Restart the unit after resume **[untested]**: a unit ordered after
   `sleep.target` (or a system-sleep hook) that waits for the SERVER hostid to
   reappear on an interface, as in option 1, and then restarts the licence
   service. Addresses the trigger found on 2026-11-13 directly; option 1
   alone does not, because lmgrd is not restarted on resume.

Decided: 1 and 2 together, 3 documented as opt-in only. Option 6 was added
after the decision and is part of the package as well.

### The `libero-flexlm` package on the working machine [verified 2026-11-18]

Package 0.1.0-3 (`flexlm/`, `aur/libero-flexlm/`) installed with pacman on
the owner's machine, against the Libero 2026.1 install that is still owned by
the owner's user. The old user unit and the separately downloaded daemons in
`/opt/microchip/flexlm` were removed first; the package uses only the daemons
in `<install>/LicenseDaemons/`.

- **Install.** `sudo libero-license install <License.dat>` created the
  system user, rewrote the licence, enabled the units and brought up all three
  vendor daemons. Libero checked out `ACTEL_BASESOC`, and simulation started
  from Libero worked. Also passed after removing the package, its state
  directory and its user, i.e. as a fresh install.
- **Wrong licence refused.** The `License.zip` kept in `/opt/microchip/flexlm`
  turned out to hold the licence of the dummy-interface experiment. `install`
  refused it because no physical interface carries its host ID.
- **Dock NIC.** The dock's Ethernet adapter appears as a PCI device behind a
  Thunderbolt bridge whose sysfs attribute `removable` reads `removable`.
  `hostid` first recommended it as a fixed wired NIC; it now walks up the
  device path, treats it as removable, and recommends Wi-Fi.
- **Ownership warning.** `install` warns five times that the daemon
  directory and binaries are not owned by root. Expected with an install owned
  by the user; it disappears once `libero-setup` installs Libero as root.
- **Signals.** The vendor daemons ignore SIGTERM: `pkill -x actlmgrd` left no
  trace in the journal. After SIGKILL, lmgrd logged `actlmgrd exited with
  status 0 signal = 17` and restarted it within the same second. lmgrd itself
  stops cleanly on SIGTERM from systemd. `lmgrd -x lmdown -x lmremove` is
  accepted and logged at start-up.
- **The real failure, reproduced.** `wlan0` was given a wrong address and
  `actlmgrd` was killed. lmgrd restarted it, and it exited with
  `status 34 (Invalid host)`; lmgrd did not restart it again. After the
  address was restored, the watchdog logged `vendor daemon not running:
  actlmgrd; restarting` 58 s after the exit, and all three daemons were up
  4 s later. Outage about one minute, no manual step.
- **Resume.** After a short suspend the resume unit restarted the service 2 s
  after wake.
- **Port wait after a restart.** When tools had been connected, the restarted
  lmgrd logged `The TCP port number in the license, 1702, is already in use`
  and started the vendor daemons only 63 s later. Without earlier client
  connections there was no wait. Every restart can therefore cost about a
  minute without a licence; lmgrd's own retry limit is five minutes. The
  watchdog now acts only once lmgrd listens on the port, so it cannot restart
  a server that is still waiting.
- **`/usr/tmp`.** The package's `/usr/tmp -> ../var/tmp` link (fix 7 of
  section 4) is in place; the `Can't make directory /usr/tmp/.flexlm` flood
  no longer appears.

Not yet observed: a long sleep in everyday use (the original trigger), and a
start of the service while NetworkManager scans, which is what the start gate
is for.

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
- `Designer/bin/fp6_env_install` **[verified 2026-11-18 by reading it]**
  needs root and is run by the installer in admin mode only. It adds the
  FlashPro6 (`1514 2009`) to `/etc/cyusb.conf`, creating the file if needed,
  and appends to `/etc/udev/rules.d/88-cyusb.rules` a rule that gives **every**
  USB device of vendor 1514 mode 666 (no group). It does not reload udev and
  touches no kernel module. With `-t DIR` it writes the two files into `DIR`
  instead. Its uninstall step does nothing, so both files stay behind. There is
  no `udev_install` in 2026.1.
- `ftdi_sio` conflict: the embedded FlashPro5 is a 4-channel FTDI device;
  channel A is JTAG, B to D are UARTs. Vendor kit docs and the ArchWiki
  describe unbinding `ftdi_sio` from interface 0 **[doc]**. Checked
  2026-11-18 on kernel 6.18 (CachyOS LTS) with the board attached
  **[verified]**: `ftdi_sio` is loaded, but its built-in match for `1514:2008`
  covers interface 2 only (module alias ending in `in02`). Interface 2, a
  UART, is bound to `ftdi_sio`; interfaces 0, 1 and 3 have no driver. The JTAG
  channel is therefore never claimed, and the unbind rule is not needed on
  this kernel. Whether the match is upstream, and since which kernel version,
  was not checked. The vendor scripts contain no `ftdi_sio` handling.
- Earlier hardware issue: scan chain failed with `TDO stuck at 1` (board
  power, JTAG-select jumper or wrong target board suspected). Programming
  worked on 2026-11-16 **[verified]**, so it was not a software problem.
- "Remote Programming and Debug Services" were skipped; not needed locally.

## 7. Desktop integration [verified]

Wrapper at `~/.local/bin/libero`, core of it as of 2026-11-17 (the owner's
copy also turns a directory argument into the one `.prjx` file inside it):

```sh
#!/bin/sh
export QT_QPA_PLATFORM=xcb
export LM_LICENSE_FILE=1702@localhost
export SNPSLMD_LICENSE_FILE=1702@localhost
export SALT_LICENSE_SERVER=1702@localhost
# Pseudo-terminal for ModelSim, see section 4.
quote() { printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }
cmd="exec env SHELL=$(quote "${SHELL:-/bin/sh}")"
cmd="$cmd /opt/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin/libero"
for arg in "$@"; do
	cmd="$cmd $(quote "$arg")"
done
SHELL=/bin/sh setsid -f script -qc "$cmd" /dev/null </dev/null >/dev/null 2>&1
```

The desktop entry in use on the owner's machine does not go through the
wrapper; its `Exec=` line sets the same variables with `env` and runs
`script -qc <launcher> /dev/null`. The entry below is the target for the
package, where `/usr/bin/libero` carries the pseudo-terminal.

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
