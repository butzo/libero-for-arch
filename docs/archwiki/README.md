# ArchWiki article draft

`Microchip_Libero_SoC.wiki` is the MediaWiki source of a rewrite of the
ArchWiki article [Microsemi Libero](https://wiki.archlinux.org/title/Microsemi_Libero),
to be moved to the title "Microchip Libero SoC" (the old title stays as a
redirect). It follows Help:Style, Help:Writing article introductions and
ArchWiki:Contributing as of the wiki snapshot of 2026-11-01 (package
`arch-wiki-docs`).

## Publishing gate

Owner's decision, 2026-11-22: nothing is published (AUR submission,
talk-page announcement, wiki edits) until every test has run and passed,
including the deferred ones:

- `libero-setup remove` and `remove --purge` on the real install;
- the progress display during a real install;
- the browser hand-off on other desktops;
- the dependency list on plain Arch (test-plan.md item 5);
- the uninstall and fresh-install rounds of test-plan.md phases 1 and 2,
  with their "Done when" criteria;
- `libero-soc` installed without `libero-flexlm`, with Libero, Synplify and
  ModelSim checking out licences from a server given by the three variables.

Order after that: packages on the AUR, then the talk-page announcement, then
some days for replies, then the rewrite in several small edits with edit
summaries, then the page move.

## Statements to recheck before publishing

| Section | Statement | Depends on |
|---|---|---|
| Uninstallation | what `libero-setup remove` and `--purge` remove | remove on the real install |
| Libero SoC | browser opens and the download is picked up | hand-off on other desktops |
| Manual installation | which packages are official, which AUR (`gtk2`, `ncurses5-compat-libs`) | plain Arch check |
| Licence server on another machine | `libero-soc` works without `libero-flexlm` | organisation-server test |
| Programmers | rule for FTDI `0403:6001` programmers | documentation only, no hardware tested |
| Programmers | FlashPro6 needs `/etc/cyusb.conf` | documentation only |
| Introduction | device families listed | Microchip's product page |
| Using a downloaded installer | a `.bin` is used without a check | `libero-setup` gives no warning for a `.bin`; if that changes, update the note |

## Talk-page announcement (draft)

To be posted on Talk:Microsemi Libero once the gate is passed:

> **Rewrite for Libero SoC 2026.1 and move to "Microchip Libero SoC"**
>
> The article describes Libero v12.1 with the InstallAnywhere installer.
> Version 2026.1 uses a Qt Installer Framework installer, bundles its own
> 64-bit Qt and needs a different set of adaptations. I plan to rewrite the
> article for 2026.1 and to move it to "Microchip Libero SoC", the product's
> current name. Draft: <link to user subpage>.
>
> Kept and updated: disk space, temporary space for the installer, licence
> variables (plus `SALT_LICENSE_SERVER` for ModelSim 2025.1 and later),
> launcher and menu entry, udev rules (now `uaccess` instead of a group), and
> the FTDI programmer ID `0403:6001`.
>
> Dropped as specific to v12.1 or older: the 2 TB disk limit, 32-bit Qt5,
> openmotif and the `libXm` edit, the `libz` replacement, the `install.def`
> quoting bug, the InstallAnywhere silent install, and `lib32-libpng12`,
> `libjpeg6-turbo`, `lib32-dbus` and `ld-lsb`, which 2026.1 does not need.
> The `ftdi_sio` blacklist is replaced by a troubleshooting entry: on current
> kernels the driver no longer claims the JTAG channel, and blacklisting it
> removes the development board's serial ports.
>
> New: installation through the AUR packages libero-soc and libero-flexlm,
> licensing and the licence server, uninstallation.

## Licence of this text

The repository declares `docs/**` as CC BY-SA 4.0 (REUSE.toml). Pages on
the ArchWiki are published under the GNU FDL 1.3 or later. The owner, as
author, can submit the text there. Contributions by others to this file need
their consent before they go to the wiki.
