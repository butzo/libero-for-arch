# libero-soc

Installs Microchip Libero SoC on Arch Linux and makes it work there. The
package contains no Microchip software: `libero-setup` runs Microchip's own
installer, which you download yourself, and the package adds what Arch is
missing. The licence server comes with the `libero-flexlm` package.

## Setup

Some dependencies are AUR packages (`libero-flexlm`, `libpng15`, and on plain
Arch `ncurses5-compat-libs`), and the 32-bit libraries for ModelSim need the
`multilib` repository. Install with an AUR helper such as `yay` or `paru`;
`makepkg -s` alone cannot resolve AUR dependencies.

1. Install Libero SoC:

   ```sh
   sudo libero-setup install
   ```

   Microchip serves its installer (a `.zip`, about 200 MB) only to a
   signed-in account, so `libero-setup` cannot fetch it alone: it opens the
   download link in your browser and waits until the file is in your download
   folder. Sign in if asked and save the file there. The tool checks the
   file's SHA-256 before it uses it. A file you already have can be passed
   with `--installer FILE`.
2. The same command then
   shows Microchip's licence agreement, taken from the installer, and
   asks you to type `I accept`. It then installs the component `Libero_SoC`
   (Libero with Synplify Pro, Identify, ModelSim and QuestaSim) into
   `/opt/microchip/Libero_SoC_<version>`. Expect about 15 minutes, a
   12.5 GB download and 34 GB on disk; 50 GB must be free. Without a
   terminal, `--accept-eula` states that you have read and accept the
   agreement.
3. Get the free licence: `libero-license hostid`, request it, then
   `sudo libero-license install License.dat` (see the `libero-flexlm`
   README).
4. Start Libero from the menu, or with `libero [project.prjx | project dir]`.

`sudo libero-setup status` checks the installation. `sudo libero-setup
remove [VERSION]` runs the vendor's uninstaller; `--purge` also removes the
saved agreement, the cached installer and the logs.

## Several versions and the menu

Each `libero-setup install` adds a version next to the ones already there, in
`/opt/microchip/Libero_SoC_<version>`; projects opened in a newer Libero are
converted for good, so old projects can stay on their version. For every
version the menu gets the four entries Microchip's own installer creates,
with its icons: "Libero SoC", "PFSoC MSS Configurator", "Program Debug"
(SmartDebug) and "FPExpress", each with the version in its name. They are
written to `/usr/local/share/applications` and start through the wrapper:

```sh
libero                               # newest Libero
libero --version 2026.1 project.prjx # a given version
libero --tool fpexpress              # also: mss, program-debug
```

`sudo libero-setup remove 2026.1` removes one version and its entries. If
the licence server used that version's daemons, it is moved to the newest
remaining one. Only the installer of the newest known version is fetched
automatically; another version's installer is passed with `--installer`.

## What the package changes on the system

| Path | Why |
|---|---|
| `/etc/redhat-release` | Says "AlmaLinux release 9.6". The vendor's start script reads it to pick a library path; without it, Libero loads an old bundled libstdc++ that clashes with Arch's libraries. Other software that reads this file will take the system for AlmaLinux. |
| `/etc/pki/tls/certs/ca-bundle.crt` | Link to Arch's CA bundle; the IP catalogue download looks for it at the RHEL path. |
| `/usr/lib/udev/rules.d/70-libero-soc.rules` | Gives the user at the seat access to Microchip programmers (USB vendor 1514). |
| `/usr/bin/libero` | Starts Libero and its tools with the right environment: X11 through XWayland, the licence server, and a pseudo-terminal, without which ModelSim cannot open from Libero. |
| `/usr/lib/libero-soc/` | Helpers of `libero-setup`, among them a reader for the resources inside Microchip's installer (agreement and icons). |

What `libero-setup install` does beyond running the vendor installer:

- It moves `/etc/redhat-release` aside while the installer runs. Otherwise the
  vendor's requirements check takes the system for RHEL and runs `yum`.
- It deletes the vendor's `/etc/udev/rules.d/88-cyusb.rules`, which makes
  every Microchip USB device writable by everyone. The package's rule
  replaces it.
- It keeps the vendor's `/etc/cyusb.conf`, which FlashPro6 programmers need.
  `libero-setup remove` removes its FlashPro6 entry again.
- It saves the agreement, a record of your consent and the four tool icons
  from the installer in `/var/lib/libero-soc/installs/<version>/`.

## Notes

- **IP cores** are downloaded per user into `~/.actel/vault`. The shared
  vault under `/opt/microchip/common` is not writable for users, and Libero
  falls back to the home directory by itself.
- **Logs:** the vendor installer's in `/var/log/libero-soc/`, Libero's own
  console output in `~/.cache/libero-soc/libero.log`.
- **Licence server elsewhere:** set `LM_LICENSE_FILE`, `SNPSLMD_LICENSE_FILE`
  and `SALT_LICENSE_SERVER` before starting `libero`.
- **Not installed:** SmartHLS, the offline IP MegaVault, and the Remote
  Programming Service.
