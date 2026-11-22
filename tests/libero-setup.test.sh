#!/bin/bash
# Tests for soc/libero-setup. Run: tests/libero-setup.test.sh
#
# Everything runs unprivileged in a temporary directory. The tool's system
# paths are moved under a fake root through LIBERO_SETUP_ROOT, and the vendor
# installer is replaced by a stub script. Like the real installer, the stub
# carries a Qt "qres" resource block after its code (agreement and icons)
# and the repository XML.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../soc/libero-setup
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
passed=0
failed=0

ok() { passed=$((passed + 1)); }
not_ok() {
	failed=$((failed + 1))
	echo "FAIL: $*" >&2
}
expect() {
	local what=$1
	shift
	if "$@" >/dev/null 2>&1; then ok; else not_ok "$what"; fi
}
refuse() {
	local what=$1
	shift
	if "$@" >/dev/null 2>&1; then not_ok "$what"; else ok; fi
}

EULA_TEXT='MICROCHIP IS WILLING TO LICENSE THE ACCOMPANYING TECHNOLOGY AND DOCUMENTATION TO YOU ONLY ON THE CONDITION THAT YOU ACCEPT ALL OF THE FOLLOWING TERMS.

1) THE MICROCHIP NON-EXCLUSIVE LICENSE AGREEMENT FOR LIBERO SOC DESIGN SUITE;
Synthetic test text.

License Rev. No. 99-000000'
OTHER_EULA_TEXT='1)  THE MICROCHIP NON-EXCLUSIVE LICENSE AGREEMENT FOR POLARFIRE STUDIO;'
REPO=http://ww1.microchip.com/downloads/aemdocuments/documents/fpga-direct/liberosoc/2026.1/90-main/linux
ICONS="libero mss smart_debug fpexpress"

# make_qres <out> <path>=<file>...: a Qt binary resource block (format 1).
make_qres() {
	python3 -I - "$@" <<'PY'
import struct, sys
out, items = sys.argv[1], sys.argv[2:]
root = {}
for item in items:
    path, src = item.split("=", 1)
    parts = path.strip("/").split("/")
    node = root
    for part in parts[:-1]:
        node = node.setdefault(part, {})
    node[parts[-1]] = open(src, "rb").read()
names, offsets, data = bytearray(), {}, bytearray()
def name(n):
    if n not in offsets:
        offsets[n] = len(names)
        names.extend(struct.pack(">HI", len(n), 0) + n.encode("utf-16-be"))
    return offsets[n]
entries, queue = [None], [(0, "", root)]
while queue:
    index, label, node = queue.pop(0)
    keys = sorted(node)
    first = len(entries)
    entries.extend([None] * len(keys))
    entries[index] = struct.pack(">IHII", name(label) if index else 0, 2, len(keys), first)
    for i, key in enumerate(keys):
        value = node[key]
        if isinstance(value, dict):
            queue.append((first + i, key, value))
        else:
            entries[first + i] = struct.pack(">IHHHI", name(key), 0, 0, 0, len(data))
            data.extend(struct.pack(">I", len(value)) + value)
tree = b"".join(entries)
data_at = 20
names_at = data_at + len(data)
tree_at = names_at + len(names)
with open(out, "wb") as f:
    f.write(b"qres" + struct.pack(">IIII", 1, tree_at, data_at, names_at) + data + names + tree)
PY
}

# make_installer <path> [with-eula] [with-libero-icon]
make_installer() {
	local path=$1 eula=${2:-yes} icon=${3:-yes} res=$W/res name
	local -a items
	cat >"$path" <<'STUB'
#!/bin/bash
# Stub of the vendor web installer.
log=$W/installer-calls
echo "$*" >>"$log"
root="" common="" cmd=""
while (($#)); do
	case $1 in
	--root) root=$2; shift ;;
	CommonDir=*) common=${1#CommonDir=} ;;
	install | purge) cmd=$1 ;;
	esac
	shift
done
[ -e "$FAKEROOT/etc/redhat-release" ] && echo present >"$W/redhat-during-install"
echo "TMPDIR=$TMPDIR" >>"$log"
if [ -n "${STUB_SLOW:-}" ] && [ "$cmd" = install ]; then
	# Like the real one: announce the sizes, download, then unpack, slowly.
	echo 'Installation space required: "0.02 GB"'
	echo 'Temporary space required: "0.01 GB"'
	echo 'Downloading archive "x.7z" for component Libero SoC Design Suite.'
	mkdir -p "$TMPDIR/remoterepo-x"
	head -c 5000000 /dev/zero >"$TMPDIR/remoterepo-x/x.7z"
	sleep 3
	echo 'Preparing to unpack components...'
	mkdir -p "$root"
	head -c 9000000 /dev/zero >"$root/payload"
	sleep 3
fi
if [ "$cmd" = install ]; then
	mkdir -p "$root/Libero_SoC/Designer/bin" "$root/LicenseDaemons" "$common"
	printf '#!/bin/sh\n' >"$root/Libero_SoC/Designer/bin/libero"
	chmod +x "$root/Libero_SoC/Designer/bin/libero"
	cat >"$root/maintenancetool" <<'MT'
#!/bin/sh
echo "maintenancetool $*" >>"$W/installer-calls"
rm -rf "$(dirname "$0")"
echo "Removal completed successfully."
MT
	chmod +x "$root/maintenancetool"
	# What fp6_env_install does as root.
	mkdir -p "$FAKEROOT/etc/udev/rules.d"
	printf 'LogFile=cyusbd.log\nPIDFile=cyusb.pid\n<VPD>\n1514 2009 Microsemi FP6 Programmer\n</VPD>\n' >"$FAKEROOT/etc/cyusb.conf"
	printf 'KERNEL=="*", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="1514", MODE="666", TAG="cyusb_dev"\n' \
		>"$FAKEROOT/etc/udev/rules.d/88-cyusb.rules"
	echo "Components installed successfully"
fi
exit "$(cat "$W/installer-exit" 2>/dev/null || echo 0)"
STUB
	mkdir -p "$res"
	printf %s "$OTHER_EULA_TEXT" >"$res/pfs.txt"
	items=("/license/license_pfs.txt=$res/pfs.txt")
	if [[ $eula == yes ]]; then
		printf %s "$EULA_TEXT" >"$res/libero.txt"
		items+=("/license/license_libero.txt=$res/libero.txt")
	fi
	for name in $ICONS; do
		[[ $name == libero && $icon != yes ]] && continue
		printf '/* XPM */\nstatic char * %s_xpm[] = {"1 1 1 1","  c None"," "};\n' "$name" >"$res/$name.xpm"
		items+=("/libero-icons/$name.xpm=$res/$name.xpm")
	done
	make_qres "$res/block" "${items[@]}"
	{
		printf '\n'
		cat "$res/block"
		printf '\0<RemoteRepositories>\n  <Url>%s</Url>\n</RemoteRepositories>\0' "$REPO"
	} >>"$path"
	chmod +x "$path"
}

fresh() {
	W=$T/$1
	FAKEROOT=$W/root
	mkdir -p "$FAKEROOT/etc" "$W/bin" "$W/user/Downloads" "$W/downloads"
	: >"$W/installer-calls"
	: >"$W/calls"
	cat >"$W/bin/udevadm" <<EOF
#!/bin/sh
echo "udevadm \$*" >>"$W/calls"
EOF
	cat >"$W/bin/update-desktop-database" <<EOF
#!/bin/sh
echo "update-desktop-database \$*" >>"$W/calls"
EOF
	cat >"$W/bin/libero-license" <<EOF
#!/bin/sh
echo "libero-license \$*" >>"$W/calls"
EOF
	# The browser: asked to open a link, it "downloads" what the test staged.
	cat >"$W/bin/xdg-open" <<EOF
#!/bin/sh
echo "xdg-open \$*" >>"$W/calls"
[ -e "$W/browser-delivers" ] && cp "$W/browser-delivers" "$W/user/Downloads/$ZIP_NAME"
exit 0
EOF
	chmod +x "$W"/bin/*
	echo 'AlmaLinux release 9.6 (Sage Margay)' >"$FAKEROOT/etc/redhat-release"
	KNOWN_SHA=none
}

ZIP_NAME=libero_soc_2026.1_online_lin.zip
# make_zip <path>: the installer packed as Microchip delivers it.
make_zip() {
	make_installer "$W/Libero_SoC_2026.1_online_lin.bin"
	(cd "$W" && zip -q -j packed.zip Libero_SoC_2026.1_online_lin.bin && rm Libero_SoC_2026.1_online_lin.bin)
	mv "$W/packed.zip" "$1"
	KNOWN_SHA=$(sha256sum "$1" | cut -d' ' -f1)
}

run() {
	env PATH="$W/bin:$PATH" W="$W" FAKEROOT="$FAKEROOT" \
		LIBERO_SETUP_TEST=1 \
		LIBERO_SETUP_ROOT="$FAKEROOT" \
		LIBERO_SETUP_MIN_FREE_GB=0 \
		LIBERO_SETUP_DOWNLOAD_DIR="$W/user/Downloads" \
		LIBERO_SETUP_KNOWN_SHA256="${KNOWN_SHA:-none}" \
		LIBERO_SETUP_WAIT=4 \
		LIBERO_SETUP_PROGRESS_INTERVAL=1 \
		LIBERO_SETUP_LIB="$HERE/../soc" \
		SUDO_USER="${RUN_SUDO_USER-tester}" \
		"$TOOL" "$@" </dev/null
}

# install_version <version>: a quiet install from a stub of that version.
install_version() {
	make_installer "$W/downloads/Libero_SoC_$1_online_lin.bin"
	run install --accept-eula --installer "$W/downloads/Libero_SoC_$1_online_lin.bin" >/dev/null 2>&1
}

V=var/lib/libero-soc/installs/2026.1
TARGET_REL=opt/microchip/Libero_SoC_2026.1
APPS=usr/local/share/applications

# --- install -----------------------------------------------------------------

fresh install-ok
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
expect "install succeeds with --accept-eula" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
expect "the vendor launcher is in place" test -x "$FAKEROOT/$TARGET_REL/Libero_SoC/Designer/bin/libero"
args=$(head -n 1 "$W/installer-calls")
expect "installer runs headless" grep -q -- '-p minimal' <<<"$args"
expect "installer gets the target" grep -q -- "--root $FAKEROOT/$TARGET_REL" <<<"$args"
expect "installer gets the common dir" grep -q -- "CommonDir=$FAKEROOT/opt/microchip/common" <<<"$args"
expect "installer installs Libero_SoC only" grep -q -- '--no-default-installations' <<<"$args"
expect "installer installs Libero_SoC" grep -q -- 'install Libero_SoC' <<<"$args"
expect "installer creates no menu entries" grep -q -- 'LINUX_NO_SHORTCUTS=true' <<<"$args"
expect "installer uses the repository named in it" grep -q -- "--set-temp-repository $REPO" <<<"$args"
expect "installer accepts the agreement only after we did" grep -q -- '--accept-licenses' <<<"$args"
expect "installer keeps its temporary files on disk" \
	grep -q "TMPDIR=$FAKEROOT/var/cache/libero-soc/tmp" "$W/installer-calls"
refuse "the fake redhat-release is moved aside during the install" test -e "$W/redhat-during-install"
expect "and is back afterwards" grep -q AlmaLinux "$FAKEROOT/etc/redhat-release"
expect "the agreement text is kept" grep -q 'FOR LIBERO SOC DESIGN SUITE' "$FAKEROOT/$V/EULA.txt"
refuse "the kept text is the Libero agreement, not the other one" grep -q 'POLARFIRE STUDIO' "$FAKEROOT/$V/EULA.txt"
expect "the acceptance is recorded with the user" grep -q 'accepted by: tester' "$FAKEROOT/$V/eula-accepted"
expect "the acceptance is recorded with the revision" grep -q 'License Rev. No. 99-000000' "$FAKEROOT/$V/eula-accepted"
for name in $ICONS; do
	expect "the $name icon is extracted by name" grep -q "${name}_xpm" "$FAKEROOT/$V/$name.xpm"
done
expect "the install dir is recorded" test "$(cat "$FAKEROOT/$V/install-dir")" = "$FAKEROOT/$TARGET_REL"
refuse "the vendor's mode 666 udev rule is removed" test -e "$FAKEROOT/etc/udev/rules.d/88-cyusb.rules"
expect "the vendor's cyusb.conf is kept" test -e "$FAKEROOT/etc/cyusb.conf"
expect "udev rules are reloaded" grep -q 'udevadm control --reload-rules' "$W/calls"
expect "a copy of the installer is kept in the cache" \
	test -x "$FAKEROOT/var/cache/libero-soc/installer/Libero_SoC_2026.1_online_lin.bin"
refuse "a second install of the same version is refused" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"

# --- menu entries --------------------------------------------------------------

E=$FAKEROOT/$APPS/libero-soc-2026.1
expect "a menu entry for Libero is written" grep -qx 'Name=Libero SoC 2026.1' "$E-libero.desktop"
expect "it starts this version through the wrapper" grep -qx 'Exec=libero --version 2026.1 %f' "$E-libero.desktop"
expect "it shows the Libero icon" grep -qx "Icon=/$V/libero.xpm" "$E-libero.desktop"
expect "it names Libero's window class" grep -qx 'StartupWMClass=libero_bin' "$E-libero.desktop"
expect "a menu entry for the MSS Configurator is written" grep -qx 'Name=PFSoC MSS Configurator 2026.1' "$E-mss.desktop"
expect "it starts the MSS Configurator" grep -qx 'Exec=libero --version 2026.1 --tool mss' "$E-mss.desktop"
expect "it shows the MSS icon" grep -qx "Icon=/$V/mss.xpm" "$E-mss.desktop"
expect "a menu entry for Program Debug is written" grep -qx 'Name=Program Debug 2026.1' "$E-program-debug.desktop"
expect "it starts SmartDebug" grep -qx 'Exec=libero --version 2026.1 --tool program-debug' "$E-program-debug.desktop"
expect "a menu entry for FPExpress is written" grep -qx 'Name=FPExpress 2026.1' "$E-fpexpress.desktop"
expect "it starts FPExpress" grep -qx 'Exec=libero --version 2026.1 --tool fpexpress' "$E-fpexpress.desktop"
expect "the menu cache is updated" grep -q "update-desktop-database -q $FAKEROOT/$APPS" "$W/calls"
if command -v desktop-file-validate >/dev/null; then
	expect "the entries are valid desktop files" desktop-file-validate "$E-libero.desktop" "$E-mss.desktop"
fi

fresh install-progress
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
out=$(STUB_SLOW=1 run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" 2>&1)
expect "a long install reports download progress against the total" \
	grep -q -E 'downloaded +[0-9.]+ of 0\.01 GB' <<<"$out"
expect "and unpacking progress against the total" \
	grep -q -E 'unpacked +[0-9.]+ of 0\.02 GB' <<<"$out"
expect "and still installs" test -x "$FAKEROOT/$TARGET_REL/Libero_SoC/Designer/bin/libero"

fresh install-sudo-hint
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
out=$(run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" 2>&1)
expect "an install through sudo names 'sudo -v' against the 5-minute stop" \
	grep -q "terminated' after about 5 minutes: run 'sudo -v'" <<<"$out"
fresh install-no-sudo-hint
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
out=$(RUN_SUDO_USER='' run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" 2>&1)
refuse "an install without sudo does not" grep -q "sudo -v" <<<"$out"

fresh install-from-zip
make_zip "$W/downloads/$ZIP_NAME"
expect "install takes the zip as downloaded" \
	run install --accept-eula --installer "$W/downloads/$ZIP_NAME"
expect "and installs from the installer inside it" test -x "$FAKEROOT/$TARGET_REL/Libero_SoC/Designer/bin/libero"

fresh install-zip-tampered
make_zip "$W/downloads/$ZIP_NAME"
KNOWN_SHA=0000000000000000000000000000000000000000000000000000000000000000
out=$(run install --accept-eula --installer "$W/downloads/$ZIP_NAME" 2>&1)
refuse "a zip with the known name but another checksum is refused" \
	run install --accept-eula --installer "$W/downloads/$ZIP_NAME"
expect "and the message says checksum" grep -q -i 'checksum' <<<"$out"
expect "and the vendor installer never ran" test ! -s "$W/installer-calls"

fresh install-already-downloaded
make_zip "$W/user/Downloads/$ZIP_NAME"
expect "install without arguments uses the zip in the user's download folder" run install --accept-eula
refuse "and does not open the browser for it" grep -q xdg-open "$W/calls"
expect "and installs" test -x "$FAKEROOT/$TARGET_REL/Libero_SoC/Designer/bin/libero"

fresh install-browser-handoff
make_zip "$W/browser-delivers"
out=$(run install --accept-eula 2>&1)
expect "install without arguments opens the download link in the browser" \
	grep -q 'xdg-open https://ww1.microchip.com/.*online_lin.zip' "$W/calls"
expect "prints the link too" grep -q 'https://ww1.microchip.com/.*online_lin.zip' <<<"$out"
expect "and installs once the download has arrived" test -x "$FAKEROOT/$TARGET_REL/Libero_SoC/Designer/bin/libero"

fresh install-wrong-download
make_zip "$W/user/Downloads/$ZIP_NAME"
KNOWN_SHA=0000000000000000000000000000000000000000000000000000000000000000
refuse "a download with the wrong checksum is never accepted" run install --accept-eula
expect "and the vendor installer never ran" test ! -s "$W/installer-calls"

fresh install-from-cache
mkdir -p "$FAKEROOT/var/cache/libero-soc"
make_installer "$FAKEROOT/var/cache/libero-soc/Libero_SoC_2026.1_online_lin.bin"
expect "install finds an installer placed in the cache" run install --accept-eula

fresh install-no-consent
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
refuse "install without a terminal and without --accept-eula fails" \
	run install --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
expect "and the vendor installer never ran" test ! -s "$W/installer-calls"
expect "and nothing was installed" test ! -e "$FAKEROOT/$TARGET_REL"

fresh install-eula-missing
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" no
expect "an installer without a readable agreement still installs with --accept-eula" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
expect "and the record says the text was not shown" grep -q 'text: not found' "$FAKEROOT/$V/eula-accepted"

fresh install-icon-missing
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" yes no
expect "a missing icon does not stop the install" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
refuse "and no icon file is written" test -e "$FAKEROOT/$V/libero.xpm"
refuse "and the entry has no Icon line" grep -q '^Icon=' "$FAKEROOT/$APPS/libero-soc-2026.1-libero.desktop"
expect "the other icons are still there" test -s "$FAKEROOT/$V/mss.xpm"

fresh install-fails
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
echo 3 >"$W/installer-exit"
refuse "a failing vendor installer fails the install" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
expect "the fake redhat-release is back after a failure" grep -q AlmaLinux "$FAKEROOT/etc/redhat-release"
refuse "no install dir is recorded after a failure" test -e "$FAKEROOT/$V/install-dir"
refuse "no menu entries are written after a failure" test -e "$FAKEROOT/$APPS/libero-soc-2026.1-libero.desktop"
expect "a failed install leaves no world-writable udev rule behind" \
	test ! -e "$FAKEROOT/etc/udev/rules.d/88-cyusb.rules"
rm -f "$W/installer-exit"
out=$(run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" 2>&1)
expect "a retry over the half-installed target is refused" test -n "$out"
expect "and the message names the cleanup command" grep -q 'maintenancetool' <<<"$out"
expect "the half-installed target is not deleted automatically" \
	test -x "$FAKEROOT/$TARGET_REL/Libero_SoC/Designer/bin/libero"

fresh install-bad-name
make_installer "$W/downloads/setup.bin"
refuse "an installer whose name has no version is refused" \
	run install --accept-eula --installer "$W/downloads/setup.bin"
refuse "and it is not copied into the cache first" \
	test -e "$FAKEROOT/var/cache/libero-soc/installer/setup.bin"

fresh install-orphaned-redhat
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
mv "$FAKEROOT/etc/redhat-release" "$FAKEROOT/etc/redhat-release.libero-setup"
run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" >/dev/null 2>&1
expect "a redhat-release left aside by an aborted run is restored" \
	grep -q AlmaLinux "$FAKEROOT/etc/redhat-release"
refuse "and the aside copy is gone" test -e "$FAKEROOT/etc/redhat-release.libero-setup"

fresh install-no-redhat
rm "$FAKEROOT/etc/redhat-release"
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
expect "install works without a redhat-release file" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
refuse "and does not create one" test -e "$FAKEROOT/etc/redhat-release"

fresh install-not-root
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
out=$(env PATH="$W/bin:$PATH" "$TOOL" install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" 2>&1 </dev/null)
expect "without the test switch install needs root" grep -q 'needs root' <<<"$out"

# --- several versions -----------------------------------------------------------

fresh side-by-side
install_version 2026.1
expect "a second version installs next to the first" \
	install_version 2026.2
expect "both are recorded" test -f "$FAKEROOT/var/lib/libero-soc/installs/2026.2/install-dir"
expect "the first one is still there" test -x "$FAKEROOT/$TARGET_REL/Libero_SoC/Designer/bin/libero"
expect "each version has its own menu entries" \
	test -f "$FAKEROOT/$APPS/libero-soc-2026.2-libero.desktop" -a -f "$FAKEROOT/$APPS/libero-soc-2026.1-libero.desktop"
out=$(run status 2>&1)
expect "status lists both versions" grep -q '2026.1 in' <<<"$out"
expect "and marks the newest as default" grep -q '2026.2 in .*(default)' <<<"$out"
out=$(run remove 2>&1)
refuse "remove without a version is refused while two are installed" run remove
expect "the message gives the command for each installed version" \
	grep -q 'sudo libero-setup remove 2026.1' <<<"$out"
expect "for the other one too" grep -q 'sudo libero-setup remove 2026.2' <<<"$out"
expect "remove names the version to remove" run remove 2026.1
refuse "the removed version's tree is gone" test -e "$FAKEROOT/$TARGET_REL"
refuse "and its menu entries" test -e "$FAKEROOT/$APPS/libero-soc-2026.1-libero.desktop"
expect "the other version stays installed" test -f "$FAKEROOT/var/lib/libero-soc/installs/2026.2/install-dir"
expect "with its entries" test -f "$FAKEROOT/$APPS/libero-soc-2026.2-libero.desktop"
expect "the shared common dir stays" test -d "$FAKEROOT/opt/microchip/common"
expect "cyusb.conf stays while a version is installed" test -e "$FAKEROOT/etc/cyusb.conf"
refuse "remove of a version that is not installed fails" run remove 2026.1
out=$(run remove 2>&1)
refuse "remove without a version is refused even when only one is installed" run remove
expect "the message lists the installed version" grep -q '2026.2' <<<"$out"
expect "and gives the command to remove it" grep -q 'sudo libero-setup remove 2026.2' <<<"$out"
expect "remove with the version works" run remove 2026.2
refuse "now cyusb.conf is gone" test -e "$FAKEROOT/etc/cyusb.conf"

# --- licence server -------------------------------------------------------------

fresh licence-untouched
install_version 2026.1
install_version 2026.2
mkdir -p "$FAKEROOT/var/lib/libero-flexlm"
echo 'SERVER localhost x 1702' >"$FAKEROOT/var/lib/libero-flexlm/License.dat"
ln -s "$FAKEROOT/opt/microchip/Libero_SoC_2026.2/LicenseDaemons" "$FAKEROOT/var/lib/libero-flexlm/daemons"
run remove 2026.1 >/dev/null 2>&1
refuse "removing a version the licence server does not use leaves it alone" grep -q 'libero-license' "$W/calls"
run remove 2026.2 >/dev/null 2>&1
refuse "with no version left the licence server cannot be moved" grep -q 'libero-license' "$W/calls"

fresh licence-repoint
install_version 2026.1
install_version 2026.2
mkdir -p "$FAKEROOT/var/lib/libero-flexlm"
echo 'SERVER localhost x 1702' >"$FAKEROOT/var/lib/libero-flexlm/License.dat"
ln -s "$FAKEROOT/opt/microchip/Libero_SoC_2026.2/LicenseDaemons" "$FAKEROOT/var/lib/libero-flexlm/daemons"
run remove 2026.2 >/dev/null 2>&1
expect "removing the version the licence server uses moves it to another one" \
	grep -q 'libero-license install /var/lib/libero-flexlm/License.dat' "$W/calls"

# --- refresh and the old layout ---------------------------------------------------

fresh refresh-migrates
install_version 2026.1
# Turn the state back into the single-install layout of releases before 0.2.
S=$FAKEROOT/var/lib/libero-soc
mv "$S/installs/2026.1/install-dir" "$S/installs/2026.1/EULA.txt" "$S/installs/2026.1/eula-accepted" "$S/"
rm -rf "$S/installs" "${FAKEROOT:?}/$APPS"
out=$(run status 2>&1)
expect "status points out the old layout" grep -q 'old layout' <<<"$out"
expect "refresh succeeds on the old layout" run refresh
expect "it moves the record into the per-version layout" test -f "$FAKEROOT/$V/install-dir"
refuse "and leaves nothing in the old place" test -e "$S/install-dir"
expect "the agreement record moves along" grep -q 'accepted by: tester' "$FAKEROOT/$V/eula-accepted"
expect "icons come from the cached installer" test -s "$FAKEROOT/$V/fpexpress.xpm"
expect "menu entries are created" test -f "$FAKEROOT/$APPS/libero-soc-2026.1-program-debug.desktop"
touch "$FAKEROOT/$APPS/libero-soc-2025.2-libero.desktop"
run refresh >/dev/null 2>&1
refuse "refresh removes entries of versions that are not installed" \
	test -e "$FAKEROOT/$APPS/libero-soc-2025.2-libero.desktop"

fresh remove-migrates
install_version 2026.1
S=$FAKEROOT/var/lib/libero-soc
mv "$S/installs/2026.1/install-dir" "$S/"
rm -rf "$S/installs"
expect "remove also works on the old layout" run remove 2026.1
refuse "and the tree is gone" test -e "$FAKEROOT/$TARGET_REL"

# --- remove ------------------------------------------------------------------

fresh remove
install_version 2026.1
printf 'KERNEL=="*", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="1514", MODE="666", TAG="cyusb_dev"\n' \
	>"$FAKEROOT/etc/udev/rules.d/88-cyusb.rules"
expect "remove succeeds" run remove 2026.1
expect "remove runs the vendor uninstaller" grep -q 'maintenancetool .*purge' "$W/installer-calls"
refuse "the tree is gone" test -e "$FAKEROOT/$TARGET_REL"
refuse "the empty common dir is gone" test -e "$FAKEROOT/opt/microchip/common"
refuse "the empty /opt/microchip is gone" test -e "$FAKEROOT/opt/microchip"
refuse "the vendor's cyusb.conf is gone" test -e "$FAKEROOT/etc/cyusb.conf"
refuse "the vendor's udev rule is gone" test -e "$FAKEROOT/etc/udev/rules.d/88-cyusb.rules"
refuse "the install dir record is gone" test -e "$FAKEROOT/$V/install-dir"
refuse "the icons are gone" test -e "$FAKEROOT/$V/libero.xpm"
refuse "the menu entries are gone" test -e "$FAKEROOT/$APPS/libero-soc-2026.1-libero.desktop"
expect "the agreement record stays without --purge" test -e "$FAKEROOT/$V/eula-accepted"
refuse "remove again fails: nothing installed" run remove 2026.1

fresh remove-keeps-foreign
install_version 2026.1
printf 'LogFile=cyusbd.log\nPIDFile=cyusb.pid\n<VPD>\n04b4 00f1 Other Cypress device\n1514 2009 Microsemi FP6 Programmer\n</VPD>\n' >"$FAKEROOT/etc/cyusb.conf"
mkdir -p "$FAKEROOT/opt/microchip/common/vault/Components"
mkdir -p "$FAKEROOT/opt/microchip/Libero_SoC_2025.2"
expect "remove succeeds with other content around" run remove 2026.1
expect "a cyusb.conf with other devices is kept" grep -q '04b4 00f1' "$FAKEROOT/etc/cyusb.conf"
refuse "but loses the FlashPro6 line" grep -q '1514 2009' "$FAKEROOT/etc/cyusb.conf"
expect "a common dir with a vault in it is kept" test -d "$FAKEROOT/opt/microchip/common/vault"
expect "another version's tree is kept" test -d "$FAKEROOT/opt/microchip/Libero_SoC_2025.2"

fresh remove-tree-gone
install_version 2026.1
rm -rf "${FAKEROOT:?}/$TARGET_REL"
expect "remove succeeds when the tree was deleted by hand" run remove 2026.1
refuse "and clears the stale record" test -e "$FAKEROOT/$V/install-dir"
expect "so that install works again" install_version 2026.1

fresh remove-no-uninstaller
install_version 2026.1
rm "$FAKEROOT/$TARGET_REL/maintenancetool"
out=$(run remove 2026.1 2>&1)
refuse "remove fails when the tree exists without its uninstaller" run remove 2026.1
expect "and names the command to delete it" grep -q 'rm -rf' <<<"$out"

fresh cyusb-without-vpd
install_version 2026.1
printf 'Setting=from another tool\n' >"$FAKEROOT/etc/cyusb.conf"
run remove 2026.1 >/dev/null 2>&1
expect "a cyusb.conf with foreign content outside a VPD block is kept" \
	grep -q 'another tool' "$FAKEROOT/etc/cyusb.conf"

fresh remove-purge
install_version 2026.1
out=$(run remove --purge 2026.1 2>&1)
expect "remove --purge succeeds" test -n "$out"
refuse "--purge removes the agreement record" test -e "$FAKEROOT/$V/eula-accepted"
refuse "--purge removes the cached installer" test -e "$FAKEROOT/var/cache/libero-soc/installer"
expect "--purge lists the per-user data it cannot remove" grep -q '.actel' <<<"$out"

# --- status ------------------------------------------------------------------

fresh status
out=$(run status 2>&1)
refuse "status fails when nothing is installed" run status
expect "and says so" grep -q 'not installed' <<<"$out"
install_version 2026.1
mkdir -p "$FAKEROOT/etc/pki/tls/certs"
ln -s /etc/ssl/certs/ca-certificates.crt "$FAKEROOT/etc/pki/tls/certs/ca-bundle.crt"
out=$(run status 2>&1)
expect "status succeeds after an install" run status
expect "status names the install" grep -q "$FAKEROOT/$TARGET_REL" <<<"$out"
expect "status counts the menu entries and icons" grep -q 'menu: 4 entries, 4 icons' <<<"$out"
expect "status shows the accepted agreement" grep -q '99-000000' <<<"$out"
rm "$FAKEROOT/etc/redhat-release"
refuse "status fails when the redhat-release shim is missing" run status

refuse "an unknown command fails" run frobnicate
out=$(run --help 2>&1)
refuse "the help text shows no lint directives" grep -q 'shellcheck' <<<"$out"
expect "the help text names remove with a version" grep -q 'remove VERSION' <<<"$out"
expect "the help text names 'sudo -v' for fingerprint logins" grep -q "run 'sudo -v' first" <<<"$out"

echo "passed: $passed, failed: $failed"
[ "$failed" -eq 0 ]
