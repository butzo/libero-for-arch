#!/bin/bash
# Tests for soc/libero, the wrapper. Run: tests/libero-wrapper.test.sh
#
# The wrapper reads its state from LIBERO_SOC_STATE. The vendor launchers are
# stubs that record how they were called; the wrapper starts them detached,
# so the tests wait for that record.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../soc/libero
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

# add_version <version>: an install with stub launchers for all four tools.
add_version() {
	local dir=$W/opt/Libero_SoC_$1 launcher
	mkdir -p "$W/state/installs/$1" "$dir/Libero_SoC/Designer/bin" "$dir/Libero_SoC/Designer/bin64"
	echo "$dir" >"$W/state/installs/$1/install-dir"
	for launcher in bin/libero bin64/pfsoc_mss bin/sdebug bin/FPExpress; do
		cat >"$dir/Libero_SoC/Designer/$launcher" <<EOF
#!/bin/sh
{
	echo "launcher=\$0"
	echo "tty=\$([ -t 0 ] && echo yes || echo no)"
	echo "QT_QPA_PLATFORM=\$QT_QPA_PLATFORM SALT_LICENSE_SERVER=\$SALT_LICENSE_SERVER"
	for arg; do echo "arg=[\$arg]"; done
} >"$W/ran.part"
mv "$W/ran.part" "$W/ran"
EOF
		chmod +x "$dir/Libero_SoC/Designer/$launcher"
	done
}

fresh() {
	W=$T/$1
	mkdir -p "$W/state" "$W/user"
}

# start <args...>: run the wrapper and wait for the launcher's record.
start() {
	rm -f "$W/ran"
	env -u LM_LICENSE_FILE -u SNPSLMD_LICENSE_FILE -u SALT_LICENSE_SERVER \
		LIBERO_SOC_STATE="$W/state" HOME="$W/user" XDG_CACHE_HOME="$W/user/.cache" \
		"$TOOL" "$@" </dev/null >"$W/out" 2>&1 || return 1
	for _ in $(seq 1 50); do
		[[ -f $W/ran ]] && return 0
		sleep 0.1
	done
	return 1
}

fresh versions
add_version 2026.1
add_version 2026.2
expect "the wrapper starts Libero" start
expect "of the newest version by default" grep -q 'Libero_SoC_2026.2/Libero_SoC/Designer/bin/libero$' "$W/ran"
expect "inside a pseudo-terminal, so that ModelSim opens its GUI" grep -q 'tty=yes' "$W/ran"
expect "with X11 through XWayland" grep -q 'QT_QPA_PLATFORM=xcb' "$W/ran"
expect "and the local licence server" grep -q 'SALT_LICENSE_SERVER=1702@localhost' "$W/ran"
expect "--version picks another version" start --version 2026.1
expect "and starts that one" grep -q 'Libero_SoC_2026.1/Libero_SoC/Designer/bin/libero$' "$W/ran"
refuse "--version with a version that is not installed fails" start --version 2025.2
expect "and says so" grep -q 'not installed' "$W/out"

fresh tools
add_version 2026.1
expect "--tool mss starts the MSS Configurator" start --tool mss
expect "from bin64" grep -q 'Designer/bin64/pfsoc_mss$' "$W/ran"
expect "--tool program-debug starts SmartDebug" start --tool program-debug
expect "from sdebug" grep -q 'Designer/bin/sdebug$' "$W/ran"
expect "--tool fpexpress starts FlashPro Express" start --version 2026.1 --tool fpexpress
expect "from FPExpress" grep -q 'Designer/bin/FPExpress$' "$W/ran"
refuse "an unknown tool fails" start --tool frobnicate

fresh arguments
add_version 2026.1
mkdir -p "$W/my project"
touch "$W/my project/design.prjx"
expect "a project directory is accepted" start "$W/my project"
expect "and stands for the .prjx inside it" grep -qF "arg=[$W/my project/design.prjx]" "$W/ran"
odd="$W/it's \$HOME \`x\` \"q\".prjx"
touch "$odd"
expect "a path with quotes, dollar signs and backquotes is passed on" start "$odd" SCRIPT:run.tcl
expect "unchanged" grep -qF "arg=[$odd]" "$W/ran"
expect "and so are further options" grep -qF 'arg=[SCRIPT:run.tcl]' "$W/ran"
mkdir -p "$W/two"
touch "$W/two/a.prjx" "$W/two/b.prjx"
refuse "a directory with two .prjx files is refused" start "$W/two"
expect "the tool's output goes to the log" test -s "$W/user/.cache/libero-soc/libero.log"

fresh missing
refuse "without any install the wrapper fails" start
expect "and says how to install" grep -q 'libero-setup install' "$W/out"

fresh legacy
add_version 2026.1
mv "$W/state/installs/2026.1/install-dir" "$W/state/install-dir"
rm -rf "$W/state/installs"
expect "the layout before 0.2 still works" start
expect "and starts that install" grep -q 'Libero_SoC_2026.1/Libero_SoC/Designer/bin/libero$' "$W/ran"

echo "passed: $passed, failed: $failed"
[ "$failed" -eq 0 ]
