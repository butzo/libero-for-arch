# Test plan: from working install to reproducible fresh install

Agreed with the owner on 2026-11-13. Background and confidence tags
(**[verified]**, **[doc]**, **[inferred]**, **[untested]**) are in
[handoff.md](handoff.md). Section numbers below are the ones shared by
handoff.md (0, 1, 1a), [findings.md](findings.md) (2 to 7, 11),
[design.md](design.md) (8, 10) and this file (9, at the end).

## Target

Anyone on Arch should get a working Libero SoC with these steps and nothing
else:

1. `yay -S libero-soc`
2. `sudo libero-setup install`: downloads and installs the vendor software,
   applies the Arch fixes, and ends by printing the MAC address to request the
   licence for, with the link.
3. Request the Silver floating licence from Microchip (manual, cannot be
   avoided).
4. `sudo libero-license install License.dat`: checks the file against the
   machine, installs it, starts the licence server.

Install comes before the licence: the licence is not needed to install, the
12.5 GB download overlaps with the wait for the licence e-mail, and the tool
that reports the host ID as FlexLM sees it lives in the vendor tree.
Step 4 takes no MAC argument; the host ID is read from the `SERVER` line.

Small problems caused by an unusual setup on the user's side are acceptable.
Hand-fixing on a plain Arch system is not.

## Ground rules

- The Arch install is disposable. The owner's productive install is in a
  Windows VM. The whole `/opt/microchip` tree, including `flexlm/`, may be
  wiped, **after** the licence file is backed up (phase 0, step 1).
- The owner runs commands that need root. The agent prepares the exact
  commands, reads the logs and records the results.
- Results go into `findings.md` with a confidence tag. Raw logs go to
  `local/logs/` and are redacted before anything is quoted in a tracked file.
- Commands marked **[untested]** are proposals. Record what actually worked.

## Phase 0: back up and learn from the current install

Nothing is removed in this phase. Each test decides something the setup tool
has to do, and is cheaper now than after a wipe.

1. **Backup** into `local/backup/` (gitignored): `License.dat` from
   `/opt/microchip/flexlm/`, the user unit `flexlm.service`, the wrapper
   `~/.local/bin/libero`, the installer-written desktop entry.
   Confirm with `git check-ignore -v local/backup/License.dat`.
2. **Host ID.** With the dock attached (two wired NICs present):

   ```sh
   /opt/microchip/flexlm/lmutil lmhostid
   ip -br link
   ```

   One host ID that is the Wi-Fi MAC: FlexLM takes a single interface and
   Wi-Fi is forced on this machine. Several host IDs: any physical NIC can
   anchor the licence, and a wired one is preferable where it is permanent.
   Decides what `libero-license hostid` prints. Note that a 32-bit `lmutil`
   and `lmhostid` also exist in `Designer/bin`; check whether they run.
3. **Fake `redhat-release`.** The vendor script
   `Designer/bin64/actel_setup_vars_nomotif` reads `/etc/redhat-release`
   unguarded (source of the repeated `cat:` errors) and skips the bundled
   `lib64/rhel` libstdc++ when it finds `AlmaLinux release 9` **[verified by
   reading the script]**. Test **[untested]**:

   ```sh
   echo 'AlmaLinux release 9.6 (Sage Margay)' | sudo tee /etc/redhat-release
   cd /opt/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/lib64/rhel
   mv libstdc++.so.6 libstdc++.so.6.link && cp -a libstdc++.so.6.orig libstdc++.so.6
   ```

   Start Libero, run place and route. Pass: no `cat:` lines, no unsupported-OS
   warning, no `GLIBCXX` error. Then the fake file replaces fix 3 of section 4.
   Fail: repeat with `AlmaLinux release 8.10 (Cerulean Leopard)`, which should
   only silence the messages, and keep the libstdc++ fix. Undo by restoring
   the symlink and removing the file.
4. **Bundled licence daemons.** Stop the user service, serve the same licence
   with `lmgrd` from `<install>/LicenseDaemons/` (licence copied to a temp
   directory, daemon paths rewritten). Pass: the healthy-start signature of
   section 5 and a Libero start without a licence popup. Decides whether the
   separate daemon download can be dropped.
5. **Library sweep.** The `ldd` sweep from section 4; map missing sonames to
   packages with `pacman -F`. Result: the real `depends=()`.
6. **Rest of the flow.** Synthesis with its log captured, one simulation
   start, programmer detection. Closes step 11 of section 9.
7. **Inventory of files outside `/opt`.** List what the vendor install and
   first runs created in the home directory (desktop entry, installer cache
   under `~/.cache/qt-installer-framework`, tool configuration folders) and in
   `/etc`. This is the checklist for phase 1. Done 2026-11-18, see "Files
   outside `/opt`" in findings.md section 3.

## Phase 1: uninstall

1. Stop and disable the user licence service.
2. Run the vendor uninstaller headlessly **[untested]**:

   ```sh
   /opt/microchip/Libero_SoC_2026.1/maintenancetool --confirm-command -d purge
   ```

   Record: exit code, prompts, duration, what remains under `/opt/microchip`
   (expected candidates: `common/`, `flexlm/`) and what remains from the
   phase 0 inventory.
3. Remove the remainder by hand and note every path. That list is what
   `libero-setup remove` must clean, split into "always" and "only with
   `--purge`" (user data such as the IP vault).
4. Remove the host changes so the machine matches a stranger's: the
   `/etc/pki/tls/certs/ca-bundle.crt` link, any fake `/etc/redhat-release`,
   the udev rule, the wrapper, the desktop entry, the user unit, and the
   packages `libpng15` and `libxml2-legacy` if `pacman -Qi` shows nothing else
   requires them.

## Phase 2: fresh install rounds

Each round is: wipe (phase 1 procedure), install, smoke test.

| Round | What it tests | What to record |
|---|---|---|
| 1 | Headless install as root, `Libero_SoC` only, with `-d -d` (candidate command in section 3) | message box ids and the answers they need, exit code, duration, installed size, writes to root's home, whether the Linux requirements check aborts on Arch, whether `CommonDir` is honoured, whether `libpng15` is needed without a GUI |
| 2 | Arch fixes chosen in phase 0, applied to a root-owned tree, Libero run as a normal user | start without errors, IP cores download into `common/vault`, permissions the vault needs |
| 3 | Licence as a system service with a dedicated user, daemons from the vendor tree, start gate and watchdog | clean start, recovery after `pkill -x actlmgrd`, behaviour during `nmcli device wifi rescan`, time to recover. Done early on 2026-11-18 against the existing install with the `libero-flexlm` package (findings.md section 5); repeat against the fresh install |
| 4 | Full journey from the Target section with the draft scripts | every manual step still needed, total time |

To settle in round 1, because the later rounds depend on it:

- **Download cost.** Each install fetches 12.5 GB. Check whether
  `--cache-path` keeps the payload, or whether the installer's
  `create-offline` command produces something later rounds can install from.
  Vendor files stay outside the repository.
- **Scripted smoke test.** Libero accepts a Tcl script on the command line
  **[doc; untested here]**:

  ```sh
  libero SCRIPT:smoke.tcl LOGFILE:smoke.log
  ```

  with `open_project` on a copy of a real project followed by
  `run_tool -name {SYNTHESIZE}`, `{PLACEROUTE}` and
  `{GENERATEPROGRAMMINGDATA}`. If it runs without a display, the smoke test is
  one command with an exit code. If not, the smoke test is the same flow by
  hand in the GUI.

### Smoke test definition

Identical after every install:

1. `libero` starts, no library errors on the terminal.
2. The licence features are available (no licence popup).
3. Synthesis, place and route and bitstream generation complete on the copy of
   the reference project.
4. From round 3 on: the programmer is detected.

## Done when

Round 4 passes on a wiped machine with no step outside the four in the Target
section, and `findings.md` carries the results with **[verified]** tags.

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
   on repeated Ctrl-C, so check how the unit stops it.

   Done 2026-11-16 **[verified]**, bundled daemons run as a transient
   systemd user unit (`lmgrd -z`): Libero started without a licence popup,
   and `actlmgrd` logged `OUT: "ACTEL_BASESOC"` one second after the
   launch. `systemctl stop` sends SIGTERM; lmgrd logged "will now shut down
   all the vendor daemons", stopped all three and exited within the same
   second, leaving no process behind. So the default `KillMode` is fine for
   the package unit. The `/usr/tmp/.flexlm` message appeared 53 times in a
   36-second run (about 1.5 per second).

   Lesson, 2026-11-17 **[verified]**: stop such a temporary unit after the
   test. The one from this test was left running, kept port 1702, and lost
   its vendor daemons to the MAC race the same evening (status 34). The next
   day the regular unit logged "The TCP port number in the license, 1702, is
   already in use" and only retried, so restarting it gave no licence until
   the leftover unit was stopped. For the package: two licence servers on
   one port fail quietly, so `libero-license status` should report a port
   that is held by a process outside the packaged unit.

   Side finding **[inferred from timing]**: the vendor launcher
   `Designer/bin/libero` puts `libero_bin` in the background and returns
   at once (exit 0 in the same second, while the licence stayed checked out
   for 11 seconds). Anything that wraps it and wants the exit status or the
   output, such as a scripted smoke test, has to redirect output to a file
   and wait for `libero_bin`, or call `libero_bin` directly.
7. Read `Designer/bin/libero` (how it builds `LD_LIBRARY_PATH`, what it does
   with `/etc/redhat-release`) and `grep -rIl '/opt/microchip'` over the
   tree to learn what `maintenancetool` relocation implies.
8. `paru -Ss libero; paru -Ss microsemi; paru -Ss flashpro` : AUR name clash check.
9. `find /opt/microchip -name '*.rules' -o -name 'udev_install' -o -name 'fp6_env_install'`
10. `lsmod | grep ftdi_sio` with the board attached; is interface 0 bound?
11. Done 2026-11-17 **[verified]**: one full flow has run on Arch. Synthesis,
    P&R, bitstream generation, programming and a simulation started from
    Libero all work, see section 4. No missing library turned up in any of
    them.
