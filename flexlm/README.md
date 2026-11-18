# libero-flexlm

Runs the FlexLM licence server that Microchip Libero SoC needs on Linux, as a
systemd service that survives sleep and Wi-Fi address randomisation.

The package contains no Microchip software. The licence daemons (`lmgrd`,
`actlmgrd`, `saltd`, `snpslmd`) are used from the Libero installation, and the
licence file is yours.

## Setup

1. Find the host ID to request the licence for:

   ```sh
   libero-license hostid
   ```

2. Request the free "Libero Silver 1Yr Floating License for Windows/Linux
   Server" for that host ID at
   <https://www.microchipdirect.com/fpga-software-products>. It arrives by
   e-mail.

3. Install it:

   ```sh
   sudo libero-license install License.dat
   ```

   This checks the file against this machine, sets the host name to
   `localhost`, points the daemon lines at the daemons of the newest Libero
   installation under `/opt/microchip`, stores the result in
   `/var/lib/libero-flexlm/License.dat`, and enables and starts the units.
   Use `--daemons DIR` for daemons in another place.

4. Libero and its tools find the server through these variables (1702 is the
   port in the licence file):

   ```sh
   LM_LICENSE_FILE=1702@localhost
   SNPSLMD_LICENSE_FILE=1702@localhost
   SALT_LICENSE_SERVER=1702@localhost
   ```

`libero-license status` tells whether the server is healthy and, if not,
which part is missing.

## Why three units

A FlexLM vendor daemon checks the host ID when it starts. If the licence is
tied to a Wi-Fi adapter and NetworkManager has randomised its address at that
moment (it does so while scanning), the daemon exits with "Invalid host" and
is not started again, while `lmgrd` keeps running. systemd then sees a healthy
service that hands out no licences. This happens on most wakes from sleep.

| Unit | What it does |
|---|---|
| `libero-flexlm.service` | Runs `lmgrd` as the user `libero-flexlm`. Before starting it waits until a physical network interface carries the licence host ID. |
| `libero-flexlm-watchdog.timer` | Every minute: if the service runs but a vendor daemon named in the licence does not, restart the service. |
| `libero-flexlm-resume.service` | Restarts the service after every resume from sleep. |

If the licence is tied to a built-in wired adapter, none of this is needed,
and it does no harm.

The watchdog restarts the service at most once every three minutes, so a
vendor daemon that never comes up does not take the working ones down every
minute. A restart ends the licence checkouts of running tools; they fetch
them again by themselves.

Every restart, including the one after resume, leaves the tools without a
licence for about a minute: `lmgrd` waits until the kernel releases the old
socket of the licence port, and starts the vendor daemons only then.
`libero-license status` shows this as "waiting for port".

## Security notes

- `lmgrd` and the vendor daemons listen on all network interfaces, as FlexLM
  does everywhere. Other machines on the network can therefore check out the
  licence. The unit switches off the remote `lmdown` and `lmremove` commands,
  so they cannot stop the server. To confine it to this machine, add a
  drop-in with `systemctl edit libero-flexlm`:

  ```ini
  [Service]
  IPAddressDeny=any
  IPAddressAllow=localhost
  ```

  Virtual machines and containers then no longer reach it.
- The service runs the daemons from the Libero installation. Whoever can
  replace those files can run code as the user `libero-flexlm`.
  `libero-license install` warns when the daemon directory is not owned by
  root or is writable by others.

## Options

- **Keep the Wi-Fi address fixed.** This removes the cause, at a privacy cost:
  the adapter then shows its real address to every network it scans. Create
  `/etc/NetworkManager/conf.d/libero-flexlm.conf`:

  ```ini
  [device-libero-flexlm]
  match-device=interface-name:wlan0
  wifi.scan-rand-mac-address=no
  ```

- **Daemons after a Libero update.** The link
  `/var/lib/libero-flexlm/daemons` points at one Libero version. Run
  `sudo libero-license install /var/lib/libero-flexlm/License.dat` again to
  move it to the newest one.

## Files

| Path | Content |
|---|---|
| `/var/lib/libero-flexlm/License.dat` | The installed licence, readable by root and the service user |
| `/var/lib/libero-flexlm/daemons` | Link to the vendor's `LicenseDaemons` directory |
| `/usr/tmp` | Link to `/var/tmp`. FlexLM insists on this path for its lock files and otherwise logs an error more than once per second. |

Logs: `journalctl -u libero-flexlm`.

Removing the package stops and disables the units and leaves
`/var/lib/libero-flexlm` in place.
