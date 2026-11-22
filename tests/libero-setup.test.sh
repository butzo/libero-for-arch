#!/bin/bash
# Tests for soc/libero-setup. Run: tests/libero-setup.test.sh
#
# Everything runs unprivileged in a temporary directory. The tool's system
# paths are moved under a fake root through LIBERO_SETUP_ROOT, and the vendor
# installer is replaced by a stub script. Like the real installer, the stub
# carries Qt-style resources after its code: a 4-byte big-endian length in
# front of the licence agreement and of the icon, and the repository XML.
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
# The real installer carries a second agreement right after the first.
OTHER_EULA_TEXT='MICROCHIP IS WILLING TO LICENSE THE ACCOMPANYING TECHNOLOGY AND DOCUMENTATION TO YOU ONLY ON THE CONDITION THAT YOU ACCEPT ALL OF THE FOLLOWING TERMS.

1)  THE MICROCHIP NON-EXCLUSIVE LICENSE AGREEMENT FOR POLARFIRE STUDIO;'
ICON_TEXT='/* XPM */
static char * test_libero_xpm[] = {
"1 1 1 1",
"  c None",
" "};'
OTHER_ICON_TEXT='/* XPM */
static char * mss_xpm[] = {
"1 1 1 1",
"  c None",
" "};'
REPO=http://ww1.microchip.com/downloads/aemdocuments/documents/fpga-direct/liberosoc/2026.1/90-main/linux

# be32 <n>: n as four big-endian bytes. The format strings are octal escapes.
# shellcheck disable=SC2059
be32() {
	printf "\\$(printf %03o $(($1 >> 24 & 255)))\\$(printf %03o $(($1 >> 16 & 255)))"
	printf "\\$(printf %03o $(($1 >> 8 & 255)))\\$(printf %03o $(($1 & 255)))"
}
# resource <text>: a length-prefixed resource, as Qt stores it.
resource() {
	be32 "$(printf %s "$1" | wc -c)"
	printf %s "$1"
}

# make_installer <path> [with-eula] [with-icon]
make_installer() {
	local path=$1 eula=${2:-yes} icon=${3:-yes}
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
	mkdir -p "$root/Libero_SoC/Designer/bin" "$common"
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
	{
		printf 'qres\0\0\0\003junk'
		if [[ $eula == yes ]]; then
			resource "$EULA_TEXT"
			resource "$OTHER_EULA_TEXT"
		fi
		printf '\0\0\0\0padding'
		resource "$OTHER_ICON_TEXT"
		[[ $icon == yes ]] && resource "$ICON_TEXT"
		printf '\0<RemoteRepositories>\n  <Url>%s</Url>\n</RemoteRepositories>\0' "$REPO"
	} >>"$path"
	chmod +x "$path"
}

fresh() {
	W=$T/$1
	FAKEROOT=$W/root
	mkdir -p "$FAKEROOT/etc" "$W/bin" "$W/user" "$W/downloads"
	: >"$W/installer-calls"
	: >"$W/calls"
	cat >"$W/bin/udevadm" <<EOF
#!/bin/sh
echo "udevadm \$*" >>"$W/calls"
EOF
	# The browser: asked to open a link, it "downloads" what the test staged.
	cat >"$W/bin/xdg-open" <<EOF
#!/bin/sh
echo "xdg-open \$*" >>"$W/calls"
[ -e "$W/browser-delivers" ] && cp "$W/browser-delivers" "$W/user/Downloads/$ZIP_NAME"
exit 0
EOF
	chmod +x "$W/bin/udevadm" "$W/bin/xdg-open"
	mkdir -p "$W/user/Downloads"
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
		LIBERO_SETUP_LICENSE_TOOL="${LICENSE_TOOL:-libero-license}" \
		SUDO_USER=tester \
		"$TOOL" "$@" </dev/null
}

STATE_REL=var/lib/libero-soc
TARGET_REL=opt/microchip/Libero_SoC_2026.1

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
expect "the agreement text is kept" grep -q 'FOR LIBERO SOC DESIGN SUITE' "$FAKEROOT/$STATE_REL/EULA.txt"
refuse "the kept text is the Libero agreement, not the next one" grep -q 'POLARFIRE STUDIO' "$FAKEROOT/$STATE_REL/EULA.txt"
expect "the acceptance is recorded with the user" grep -q 'accepted by: tester' "$FAKEROOT/$STATE_REL/eula-accepted"
expect "the acceptance is recorded with the revision" grep -q 'License Rev. No. 99-000000' "$FAKEROOT/$STATE_REL/eula-accepted"
expect "the Libero icon is extracted" cmp -s "$FAKEROOT/$STATE_REL/libero.xpm" <(printf %s "$ICON_TEXT")
expect "the install dir is recorded" test "$(cat "$FAKEROOT/$STATE_REL/install-dir")" = "$FAKEROOT/$TARGET_REL"
refuse "the vendor's mode 666 udev rule is removed" test -e "$FAKEROOT/etc/udev/rules.d/88-cyusb.rules"
expect "the vendor's cyusb.conf is kept" test -e "$FAKEROOT/etc/cyusb.conf"
expect "udev rules are reloaded" grep -q 'udevadm control --reload-rules' "$W/calls"
expect "a copy of the installer is kept in the cache" \
	test -x "$FAKEROOT/var/cache/libero-soc/installer/Libero_SoC_2026.1_online_lin.bin"
refuse "a second install refuses an existing target" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"

fresh install-progress
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
out=$(STUB_SLOW=1 run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" 2>&1)
expect "a long install reports download progress against the total" \
	grep -q -E 'downloaded +[0-9.]+ of 0\.01 GB' <<<"$out"
expect "and unpacking progress against the total" \
	grep -q -E 'unpacked +[0-9.]+ of 0\.02 GB' <<<"$out"
expect "and still installs" test -x "$FAKEROOT/$TARGET_REL/Libero_SoC/Designer/bin/libero"

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

fresh install-no-installer
refuse "install without any installer fails" run install --accept-eula
out=$(run install --accept-eula 2>&1)
expect "and says where to get one" grep -q 'microchip.com' <<<"$out"

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
expect "and the record says the text was not shown" grep -q 'text: not found' "$FAKEROOT/$STATE_REL/eula-accepted"

fresh install-icon-missing
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" yes no
expect "a missing icon does not stop the install" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
refuse "and no icon file is written" test -e "$FAKEROOT/$STATE_REL/libero.xpm"

fresh install-fails
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
echo 3 >"$W/installer-exit"
refuse "a failing vendor installer fails the install" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
expect "the fake redhat-release is back after a failure" grep -q AlmaLinux "$FAKEROOT/etc/redhat-release"
refuse "no install dir is recorded after a failure" test -e "$FAKEROOT/$STATE_REL/install-dir"

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

# --- remove ------------------------------------------------------------------

fresh remove
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" >/dev/null 2>&1
printf 'KERNEL=="*", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="1514", MODE="666", TAG="cyusb_dev"\n' \
	>"$FAKEROOT/etc/udev/rules.d/88-cyusb.rules"
expect "remove succeeds" run remove
expect "remove runs the vendor uninstaller" grep -q 'maintenancetool .*purge' "$W/installer-calls"
refuse "the tree is gone" test -e "$FAKEROOT/$TARGET_REL"
refuse "the empty common dir is gone" test -e "$FAKEROOT/opt/microchip/common"
refuse "the empty /opt/microchip is gone" test -e "$FAKEROOT/opt/microchip"
refuse "the vendor's cyusb.conf is gone" test -e "$FAKEROOT/etc/cyusb.conf"
refuse "the vendor's udev rule is gone" test -e "$FAKEROOT/etc/udev/rules.d/88-cyusb.rules"
refuse "the install dir record is gone" test -e "$FAKEROOT/$STATE_REL/install-dir"
refuse "the icon is gone" test -e "$FAKEROOT/$STATE_REL/libero.xpm"
expect "the agreement record stays without --purge" test -e "$FAKEROOT/$STATE_REL/eula-accepted"
refuse "remove again fails: nothing installed" run remove

fresh remove-keeps-foreign
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" >/dev/null 2>&1
printf 'LogFile=cyusbd.log\nPIDFile=cyusb.pid\n<VPD>\n04b4 00f1 Other Cypress device\n1514 2009 Microsemi FP6 Programmer\n</VPD>\n' >"$FAKEROOT/etc/cyusb.conf"
mkdir -p "$FAKEROOT/opt/microchip/common/vault/Components"
mkdir -p "$FAKEROOT/opt/microchip/Libero_SoC_2025.2"
expect "remove succeeds with other content around" run remove
expect "a cyusb.conf with other devices is kept" grep -q '04b4 00f1' "$FAKEROOT/etc/cyusb.conf"
refuse "but loses the FlashPro6 line" grep -q '1514 2009' "$FAKEROOT/etc/cyusb.conf"
expect "a common dir with a vault in it is kept" test -d "$FAKEROOT/opt/microchip/common/vault"
expect "another version's tree is kept" test -d "$FAKEROOT/opt/microchip/Libero_SoC_2025.2"

fresh remove-tree-gone
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" >/dev/null 2>&1
rm -rf "${FAKEROOT:?}/$TARGET_REL"
expect "remove succeeds when the tree was deleted by hand" run remove
refuse "and clears the stale record" test -e "$FAKEROOT/$STATE_REL/install-dir"
expect "so that install works again" \
	run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"

fresh remove-no-uninstaller
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" >/dev/null 2>&1
rm "$FAKEROOT/$TARGET_REL/maintenancetool"
out=$(run remove 2>&1)
refuse "remove fails when the tree exists without its uninstaller" run remove
expect "and names the command to delete it" grep -q 'rm -rf' <<<"$out"

fresh cyusb-without-vpd
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" >/dev/null 2>&1
printf 'Setting=from another tool\n' >"$FAKEROOT/etc/cyusb.conf"
run remove >/dev/null 2>&1
expect "a cyusb.conf with foreign content outside a VPD block is kept" \
	grep -q 'another tool' "$FAKEROOT/etc/cyusb.conf"

fresh remove-purge
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" >/dev/null 2>&1
out=$(run remove --purge 2>&1)
expect "remove --purge succeeds" test -n "$out"
refuse "--purge removes the agreement record" test -e "$FAKEROOT/$STATE_REL/eula-accepted"
refuse "--purge removes the cached installer" test -e "$FAKEROOT/var/cache/libero-soc/installer"
expect "--purge lists the per-user data it cannot remove" grep -q '.actel' <<<"$out"

# --- status ------------------------------------------------------------------

fresh status
out=$(run status 2>&1)
refuse "status fails when nothing is installed" run status
expect "and says so" grep -q 'not installed' <<<"$out"
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" >/dev/null 2>&1
mkdir -p "$FAKEROOT/etc/pki/tls/certs"
ln -s /etc/ssl/certs/ca-certificates.crt "$FAKEROOT/etc/pki/tls/certs/ca-bundle.crt"
out=$(run status 2>&1)
expect "status succeeds after an install" run status
expect "status names the install" grep -q "$FAKEROOT/$TARGET_REL" <<<"$out"
expect "status shows the accepted agreement" grep -q '99-000000' <<<"$out"
rm "$FAKEROOT/etc/redhat-release"
refuse "status fails when the redhat-release shim is missing" run status

# --- licence hints: libero-flexlm is optional ---------------------------------

fresh licence-local
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
printf '#!/bin/sh\nexit 0\n' >"$W/bin/fake-libero-license"
chmod +x "$W/bin/fake-libero-license"
out=$(LICENSE_TOOL=fake-libero-license run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" 2>&1)
expect "with libero-license, install names its next steps" grep -q 'libero-license hostid' <<<"$out"
out=$(LICENSE_TOOL=fake-libero-license run status 2>&1)
expect "with libero-license, status points to its status" grep -q 'libero-license status' <<<"$out"

fresh licence-remote
make_installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin"
out=$(LICENSE_TOOL=no-such-licence-tool run install --accept-eula --installer "$W/downloads/Libero_SoC_2026.1_online_lin.bin" 2>&1)
refuse "without libero-license, install does not name it" grep -q 'libero-license hostid' <<<"$out"
expect "but offers the libero-flexlm package" grep -q 'libero-flexlm' <<<"$out"
expect "and the variables for another server" grep -q 'SALT_LICENSE_SERVER' <<<"$out"
out=$(LICENSE_TOOL=no-such-licence-tool run status 2>&1)
refuse "without libero-license, status does not point to it" grep -q 'libero-license status' <<<"$out"
expect "but says that no local server is installed" grep -q 'libero-flexlm' <<<"$out"

refuse "an unknown command fails" run frobnicate

echo "passed: $passed, failed: $failed"
[ "$failed" -eq 0 ]
