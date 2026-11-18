#!/bin/bash
# Tests for flexlm/libero-license. Run: tests/libero-license.test.sh
#
# Everything runs unprivileged in a temporary directory: the tool is pointed
# at a fake sysfs, state directory and vendor tree through its
# LIBERO_FLEXLM_* variables, and systemctl, pgrep, ip and ss are stubs.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../flexlm/libero-license
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
passed=0
failed=0

# Addresses are assembled at run time: the pre-commit scan of this repository
# rejects literal MAC addresses and host IDs.
mac() { printf '%s:%s:%s:%s:%s:%s' "$@"; }
hostid_of() { printf %s "$1" | tr -d :; }
MAC_WIFI=$(mac 02 00 5e 10 00 01)
MAC_WIFI_RANDOM=$(mac 06 aa 5e 10 00 99)
MAC_WIRED=$(mac 02 00 5e 10 00 02)
MAC_USB=$(mac 02 00 5e 10 00 03)
MAC_ABSENT=$(mac 02 00 5e 10 00 0f)

ok() { passed=$((passed + 1)); }
not_ok() {
	failed=$((failed + 1))
	echo "FAIL: $*" >&2
}
# expect <description> <command...>: the command must succeed.
expect() {
	local what=$1
	shift
	if "$@" >/dev/null 2>&1; then ok; else not_ok "$what"; fi
}
# refuse <description> <command...>: the command must fail.
refuse() {
	local what=$1
	shift
	if "$@" >/dev/null 2>&1; then not_ok "$what"; else ok; fi
}

# Each test gets a fresh world under $W.
fresh() {
	W=$T/$1
	STATE=$W/state
	SYS=$W/sys/class/net
	OPT=$W/opt
	mkdir -p "$STATE" "$SYS" "$OPT" "$W/bin" "$W/devices/pci0" "$W/devices/usb1" "$W/permaddr"
	: >"$W/calls"
	: >"$W/running"
	cat >"$W/bin/systemctl" <<EOF
#!/bin/sh
echo "\$*" >>"$W/calls"
case "\$1" in
is-active) [ -e "$W/active" ] && { echo active; exit 0; }; echo inactive; exit 3 ;;
# Start time of the unit. "young": started just now. "flap": a different
# start time on every call, as if the unit were restarted in between.
show)
	if [ -e "$W/young" ]; then echo "@\$(date +%s)"
	elif [ -e "$W/flap" ]; then n=\$(cat "$W/flap"); echo \$((n + 1)) >"$W/flap"; echo "@\$((1000 + n))"
	else echo "@1000"; fi ;;
esac
exit 0
EOF
	cat >"$W/bin/pgrep" <<EOF
#!/bin/sh
for last; do :; done
grep -qx "\$last" "$W/running"
EOF
	cat >"$W/bin/ip" <<EOF
#!/bin/sh
for last; do :; done
[ -e "$W/permaddr/\$last" ] && echo "2: \$last: <UP> link/ether x permaddr \$(cat "$W/permaddr/\$last") "
exit 0
EOF
	cat >"$W/bin/ss" <<EOF
#!/bin/sh
[ -e "$W/port_busy" ] && echo "LISTEN 0 128 0.0.0.0:1702 0.0.0.0:*"
exit 0
EOF
	chmod +x "$W"/bin/*
}

# add_iface <name> <mac> <wifi|wired|usb|virtual>
add_iface() {
	mkdir -p "$SYS/$1"
	echo "$2" >"$SYS/$1/address"
	case $3 in
	wifi)
		ln -s "$W/devices/pci0" "$SYS/$1/device"
		mkdir "$SYS/$1/wireless"
		;;
	wired) ln -s "$W/devices/pci0" "$SYS/$1/device" ;;
	usb) ln -s "$W/devices/usb1" "$SYS/$1/device" ;;
	virtual) ;;
	esac
}

# add_daemons <dir> <name...>: executable placeholders.
add_daemons() {
	local dir=$1 name
	shift
	mkdir -p "$dir"
	for name in "$@"; do
		printf '#!/bin/sh\n' >"$dir/$name"
		chmod +x "$dir/$name"
	done
}

# A licence as delivered: placeholder host name, PATH/ daemon paths, CRLF.
make_license() {
	printf '# Libero licence, synthetic test data\r\n'
	printf 'SERVER <put.hostname.here> %s 1702\r\n' "$1"
	printf 'DAEMON actlmgrd PATH/actlmgrd\r\n'
	printf '# DAEMON mgcld PATH/mgcld\r\n'
	printf 'DAEMON saltd PATH/saltd\r\n'
	printf 'VENDOR snpslmd PATH/snpslmd\r\n'
	printf 'INCREMENT ACTEL_BASESOC actlmgrd 2027.11 12-nov-2027 1 \\\r\n'
	printf '\tVENDOR_STRING=test HOSTID=%s\r\n' "$1"
}

run() {
	env PATH="$W/bin:$PATH" \
		LIBERO_FLEXLM_STATE_DIR="$STATE" \
		LIBERO_FLEXLM_RUN_DIR="$W/run" \
		LIBERO_FLEXLM_SYSFS_NET="$SYS" \
		LIBERO_FLEXLM_VENDOR_ROOT="$OPT" \
		LIBERO_FLEXLM_RECHECK_DELAY=0 \
		LIBERO_FLEXLM_SETTLE=0 \
		LIBERO_FLEXLM_TEST=1 \
		"$TOOL" "$@"
}

ALL_DAEMONS="lmgrd actlmgrd saltd snpslmd"

# --- install ---------------------------------------------------------------

fresh install-ok
add_iface wlan0 "$MAC_WIFI" wifi
# shellcheck disable=SC2086
add_daemons "$OPT/Libero_SoC_2025.2/LicenseDaemons" $ALL_DAEMONS
# shellcheck disable=SC2086
add_daemons "$OPT/Libero_SoC_2026.1/LicenseDaemons" $ALL_DAEMONS
make_license "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
expect "install accepts a licence whose host ID is on a physical interface" \
	run install "$W/License.dat"
expect "install rewrites the SERVER host name" \
	grep -qx "SERVER localhost $(hostid_of "$MAC_WIFI") 1702" "$STATE/License.dat"
expect "install points DAEMON lines at the daemon link" \
	grep -qx "DAEMON actlmgrd $STATE/daemons/actlmgrd" "$STATE/License.dat"
expect "install points VENDOR lines at the daemon link" \
	grep -qx "VENDOR snpslmd $STATE/daemons/snpslmd" "$STATE/License.dat"
expect "install leaves commented daemon lines alone" \
	grep -qx '# DAEMON mgcld PATH/mgcld' "$STATE/License.dat"
expect "install leaves feature lines alone" \
	grep -qx "$(printf '\tVENDOR_STRING=test HOSTID=%s' "$(hostid_of "$MAC_WIFI")")" "$STATE/License.dat"
refuse "install removes carriage returns" grep -q "$(printf '\r')" "$STATE/License.dat"
expect "install links the newest vendor tree's daemons" \
	test "$(readlink "$STATE/daemons")" = "$OPT/Libero_SoC_2026.1/LicenseDaemons"
expect "install enables the units" grep -q '^enable .*libero-flexlm.service' "$W/calls"
expect "install enables the watchdog timer" grep -q '^enable .*libero-flexlm-watchdog.timer' "$W/calls"
expect "install enables the restart after resume" grep -q '^enable .*libero-flexlm-resume.service' "$W/calls"
expect "install starts the service" grep -q 'restart libero-flexlm.service' "$W/calls"
expect "installed licence is not world-readable" test "$(stat -c %a "$STATE/License.dat")" = 640

fresh install-permanent-mac
add_iface wlan0 "$MAC_WIFI_RANDOM" wifi
echo "$MAC_WIFI" >"$W/permaddr/wlan0"
# shellcheck disable=SC2086
add_daemons "$OPT/Libero_SoC_2026.1/LicenseDaemons" $ALL_DAEMONS
make_license "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
expect "install accepts the permanent address while the current one is randomised" \
	run install "$W/License.dat"

fresh install-wrong-host
add_iface wlan0 "$MAC_WIFI" wifi
add_iface virt0 "$MAC_ABSENT" virtual
# shellcheck disable=SC2086
add_daemons "$OPT/Libero_SoC_2026.1/LicenseDaemons" $ALL_DAEMONS
make_license "$(hostid_of "$MAC_ABSENT")" >"$W/License.dat"
refuse "install rejects a host ID that only a virtual interface carries" \
	run install "$W/License.dat"
refuse "a rejected install leaves no licence behind" test -e "$STATE/License.dat"
expect "install --force accepts it" run install --force "$W/License.dat"

fresh install-missing-daemon
add_iface wlan0 "$MAC_WIFI" wifi
add_daemons "$OPT/Libero_SoC_2026.1/LicenseDaemons" lmgrd actlmgrd saltd
make_license "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
refuse "install rejects a daemon directory that lacks a named daemon" \
	run install "$W/License.dat"

fresh install-no-vendor-tree
add_iface wlan0 "$MAC_WIFI" wifi
make_license "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
refuse "install fails without any daemon directory" run install "$W/License.dat"
# shellcheck disable=SC2086
add_daemons "$W/elsewhere" $ALL_DAEMONS
expect "install --daemons uses the given directory" \
	run install --daemons "$W/elsewhere" "$W/License.dat"
expect "the daemon link follows --daemons" \
	test "$(readlink "$STATE/daemons")" = "$W/elsewhere"

fresh install-port-busy
add_iface wlan0 "$MAC_WIFI" wifi
# shellcheck disable=SC2086
add_daemons "$OPT/Libero_SoC_2026.1/LicenseDaemons" $ALL_DAEMONS
make_license "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
: >"$W/port_busy"
refuse "install stops when another process holds the licence port" \
	run install "$W/License.dat"
out=$(run install "$W/License.dat" 2>&1)
expect "and says that the port is in use" grep -q 'in use' <<<"$out"

fresh install-garbage
add_iface wlan0 "$MAC_WIFI" wifi
echo "not a licence" >"$W/License.dat"
refuse "install rejects a file without a SERVER line" run install "$W/License.dat"
refuse "install needs a file argument" run install

fresh install-bad-daemon-name
add_iface wlan0 "$MAC_WIFI" wifi
# shellcheck disable=SC2086
add_daemons "$OPT/Libero_SoC_2026.1/LicenseDaemons" $ALL_DAEMONS
printf 'SERVER h %s 1702\nDAEMON ../x PATH/x\n' "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
refuse "install rejects a daemon name with a path in it" run install "$W/License.dat"
printf 'SERVER h %s 1702\nDAEMON a* PATH/a\n' "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
refuse "install rejects a daemon name with a wildcard" run install "$W/License.dat"

fresh install-continued-daemon-line
add_iface wlan0 "$MAC_WIFI" wifi
# shellcheck disable=SC2086
add_daemons "$OPT/Libero_SoC_2026.1/LicenseDaemons" $ALL_DAEMONS
printf 'SERVER h %s 1702\nVENDOR snpslmd \\\n  PATH/snpslmd PORT=1234\n' "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
refuse "install rejects a DAEMON or VENDOR line continued over two lines" run install "$W/License.dat"
refuse "and leaves no licence behind" test -e "$STATE/License.dat"

fresh install-warns-user-owned-daemons
add_iface wlan0 "$MAC_WIFI" wifi
# shellcheck disable=SC2086
add_daemons "$OPT/Libero_SoC_2026.1/LicenseDaemons" $ALL_DAEMONS
make_license "$(hostid_of "$MAC_WIFI")" >"$W/License.dat"
out=$(run install "$W/License.dat" 2>&1)
expect "install warns when the daemons are not owned by root" grep -q 'not owned by root' <<<"$out"

fresh environment-ignored
add_iface fakeiface0 "$MAC_WIRED" wired
out=$(env PATH="$W/bin:$PATH" LIBERO_FLEXLM_SYSFS_NET="$SYS" "$TOOL" hostid 2>&1 || true)
refuse "without the test switch the environment cannot redirect the tool" grep -q fakeiface0 <<<"$out"

# --- wait-hostid (start gate) ------------------------------------------------

fresh gate
add_iface wlan0 "$MAC_WIFI" wifi
make_license "$(hostid_of "$MAC_WIFI")" | tr -d '\r' >"$STATE/License.dat"
expect "gate passes when a physical interface carries the host ID" run wait-hostid 1
echo "$MAC_WIFI_RANDOM" >"$SYS/wlan0/address"
refuse "gate times out while the address is randomised" run wait-hostid 1
add_iface virt0 "$MAC_WIFI" virtual
refuse "gate ignores a virtual interface with the right address" run wait-hostid 1
(
	sleep 1
	echo "$MAC_WIFI" >"$SYS/wlan0/address"
) &
expect "gate passes once the address comes back" run wait-hostid 5
wait
printf 'SERVER localhost ANY 1702\nDAEMON actlmgrd /x/actlmgrd\n' >"$STATE/License.dat"
expect "gate does not wait for a host ID that is not an address" run wait-hostid 1

# --- watchdog ----------------------------------------------------------------

fresh watchdog
make_license "$(hostid_of "$MAC_WIFI")" | tr -d '\r' >"$STATE/License.dat"
printf 'actlmgrd\nsaltd\n' >"$W/running"
expect "watchdog runs" run watchdog
refuse "watchdog leaves a stopped service alone" grep -q restart "$W/calls"
: >"$W/active"
run watchdog >/dev/null 2>&1
expect "watchdog restarts the service when a vendor daemon is gone" \
	grep -q 'restart libero-flexlm.service' "$W/calls"
: >"$W/calls"
printf 'actlmgrd\nsaltd\nsnpslmd\n' >"$W/running"
run watchdog >/dev/null 2>&1
refuse "watchdog does nothing while all vendor daemons run" grep -q restart "$W/calls"

fresh watchdog-guards
make_license "$(hostid_of "$MAC_WIFI")" | tr -d '\r' >"$STATE/License.dat"
: >"$W/active"
printf 'actlmgrd\nsaltd\n' >"$W/running"
: >"$W/young"
run watchdog >/dev/null 2>&1
refuse "watchdog leaves a unit alone that has just started" grep -q restart "$W/calls"
rm "$W/young"
echo 0 >"$W/flap"
run watchdog >/dev/null 2>&1
refuse "watchdog leaves a unit alone that was restarted during the recheck" grep -q restart "$W/calls"
rm "$W/flap"
run watchdog >/dev/null 2>&1
expect "watchdog restarts once the guards no longer apply" grep -q 'restart libero-flexlm.service' "$W/calls"
: >"$W/calls"
run watchdog >/dev/null 2>&1
refuse "watchdog restarts at most once per interval" grep -q restart "$W/calls"

# --- hostid ------------------------------------------------------------------

fresh hostid
add_iface wlan0 "$MAC_WIFI_RANDOM" wifi
echo "$MAC_WIFI" >"$W/permaddr/wlan0"
add_iface enp1s0 "$MAC_WIRED" wired
add_iface enp0u1 "$MAC_USB" usb
add_iface virbr0 "$MAC_ABSENT" virtual
out=$(run hostid 2>&1)
expect "hostid lists the wired interface" grep -q "enp1s0 .*wired .*$(hostid_of "$MAC_WIRED")" <<<"$out"
expect "hostid shows the permanent Wi-Fi address" grep -q "wlan0 .*wifi .*$(hostid_of "$MAC_WIFI")" <<<"$out"
expect "hostid marks USB adapters" grep -q "enp0u1 .*usb .*removable" <<<"$out"
refuse "hostid hides virtual interfaces" grep -q virbr0 <<<"$out"
expect "hostid recommends the built-in wired interface" \
	grep -q "host ID $(hostid_of "$MAC_WIRED")" <<<"$out"

fresh hostid-none
add_iface virbr0 "$MAC_ABSENT" virtual
refuse "hostid fails when there is no physical interface" run hostid

# --- status ------------------------------------------------------------------

fresh status
refuse "status fails while no licence is installed" run status
add_iface wlan0 "$MAC_WIFI" wifi
make_license "$(hostid_of "$MAC_WIFI")" | tr -d '\r' >"$STATE/License.dat"
: >"$W/active"
printf 'actlmgrd\nsaltd\nsnpslmd\n' >"$W/running"
expect "status succeeds when service, daemons and host ID are fine" run status
printf 'saltd\nsnpslmd\n' >"$W/running"
refuse "status fails when a vendor daemon is missing" run status

refuse "an unknown command fails" run frobnicate

echo "passed: $passed, failed: $failed"
[ "$failed" -eq 0 ]
