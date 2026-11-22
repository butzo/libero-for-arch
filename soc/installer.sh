# shellcheck shell=bash
# installer.sh: obtaining and checking the vendor installer file. Sourced by
# libero-setup, whose settings and helpers (die, info, warn, KNOWN_*,
# CACHE_DIR, DOWNLOAD_DIR, TMP_FILES and others) it uses.

sha256_of() { sha256sum -- "$1" | cut -d' ' -f1; }

# The download folder of the user who called sudo.
user_download_dir() {
	local user=${SUDO_USER:-} home dir
	if [[ -n $DOWNLOAD_DIR ]]; then
		echo "$DOWNLOAD_DIR"
		return
	fi
	[[ -n $user && $user != root ]] || return 1
	home=$(getent passwd "$user" | cut -d: -f6)
	[[ -n $home ]] || return 1
	dir=$(runuser -u "$user" -- xdg-user-dir DOWNLOAD 2>/dev/null || true)
	[[ -n $dir && -d $dir ]] || dir=$home/Downloads
	echo "$dir"
}

# Best effort: the link is printed as well, in case no browser opens.
open_in_browser() {
	local url=$1 user=${SUDO_USER:-} uid display
	if [[ -n ${LIBERO_SETUP_TEST:-} ]]; then
		xdg-open "$url" >/dev/null 2>&1 || true
		return 0
	fi
	[[ -n $user && $user != root ]] || return 0
	uid=$(id -u "$user")
	display=$(find "/run/user/$uid" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' 2>/dev/null | head -n 1)
	runuser -u "$user" -- env \
		XDG_RUNTIME_DIR="/run/user/$uid" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
		${display:+WAYLAND_DISPLAY="$display"} \
		xdg-open "$url" >/dev/null 2>&1 || true
}

# wait_for_download <dir>: print the zip's path once it is complete. A file
# counts as complete when it stopped growing and has the known checksum.
wait_for_download() {
	local file=$1/$KNOWN_ZIP waited=0 size last=-1
	while ((waited < WAIT_SECONDS)); do
		if [[ -f $file ]]; then
			size=$(stat -c %s -- "$file")
			if ((size > 0 && size == last)) && [[ $(sha256_of "$file") == "$KNOWN_SHA256" ]]; then
				echo "$file"
				return 0
			fi
			last=$size
		fi
		sleep 2
		waited=$((waited + 2))
	done
	return 1
}

# Prints the installer to use. Messages go to stderr: stdout is the result.
# Order: --installer, a file put into the cache by hand, the root-owned copy
# kept from an earlier install of the known version, then the browser.
find_installer() {
	local given=$1 newest="" dir file
	if [[ -n $given ]]; then
		[[ -f $given && -r $given ]] || die "cannot read $given"
		echo "$given"
		return
	fi
	if [[ -d $CACHE_DIR ]]; then
		newest=$(find "$CACHE_DIR" -maxdepth 1 -type f \( -iname '*_online_lin.bin' -o -iname '*_online_lin.zip' \) \
			-printf '%T@ %p\n' | sort -n | tail -n 1 | cut -d' ' -f2-)
	fi
	if [[ -n $newest ]]; then
		echo "$newest"
		return
	fi
	file=$CACHE_DIR/installer/Libero_SoC_${KNOWN_VERSION}_online_lin.bin
	if [[ -f $file ]]; then
		info "Using the installer kept from an earlier install: $file" >&2
		echo "$file"
		return
	fi
	dir=$(user_download_dir) || die "cannot tell whose browser to use. Run this with sudo from your own user,
or download $KNOWN_URL
yourself and pass it with --installer."
	if [[ -f $dir/$KNOWN_ZIP && $(sha256_of "$dir/$KNOWN_ZIP") == "$KNOWN_SHA256" ]]; then
		info "Using $dir/$KNOWN_ZIP" >&2
		echo "$dir/$KNOWN_ZIP"
		return
	fi
	cat >&2 <<EOF
==> Microchip serves the installer only to a signed-in account, so your
    browser has to download it. Opening this link now:
      $KNOWN_URL
    Sign in if asked and save the file to $dir.
    Waiting for $KNOWN_ZIP (Ctrl-C to stop) ...
EOF
	open_in_browser "$KNOWN_URL"
	file=$(wait_for_download "$dir") || die "no complete $KNOWN_ZIP with the expected checksum appeared in $dir.
Download $KNOWN_URL
and run this again, or pass the file with --installer. More: $DOWNLOAD_URL"
	info "Download complete and verified." >&2
	echo "$file"
}

# prepare_installer <file>: a root-owned copy of the .bin in the cache. The
# name is checked before anything is copied, and the copy stays private
# until it is in place, so --installer cannot be used to read other files.
prepare_installer() {
	local source=$1 dir=$CACHE_DIR/installer member staging bin sum
	case ${source,,} in
	*_online_lin.zip) ;;
	*_online_lin.bin) version_of "$source" >/dev/null ;;
	*) die "$(basename "$source") is not a Libero web installer (expected *_online_lin.zip or Libero_SoC_<version>_online_lin.bin)" ;;
	esac
	mkdir -p "$dir"
	staging=$(mktemp -d "$dir/.staging.XXXXXX")
	TMP_FILES+=("$staging")
	case ${source,,} in
	*.zip)
		# Work on a private copy, so that what was verified is what is unpacked.
		install -m 0600 -- "$source" "$staging/installer.zip"
		if [[ $(basename "${source,,}") == "$KNOWN_ZIP" ]]; then
			sum=$(sha256_of "$staging/installer.zip")
			[[ $sum == "$KNOWN_SHA256" ]] || die "checksum mismatch for $source
  expected $KNOWN_SHA256
  found    $sum
The file is incomplete, or not the installer this package was made for."
		else
			warn "no checksum is known for $(basename "$source"); it cannot be verified"
		fi
		source=$staging/installer.zip
		member=$(unzip -Z1 "$source" | awk 'tolower($0) ~ /_online_lin\.bin$/')
		member=${member%%$'\n'*}
		[[ -n $member ]] || die "$source contains no *_online_lin.bin"
		version_of "$member" >/dev/null
		unzip -o -j -q "$source" "$member" -d "$staging"
		bin=$staging/$(basename "$member")
		;;
	*)
		install -m 0700 -- "$source" "$staging/$(basename "$source")"
		bin=$staging/$(basename "$source")
		;;
	esac
	chmod 0755 "$bin"
	mv -f -- "$bin" "$dir/$(basename "$bin")"
	echo "$dir/$(basename "$bin")"
}

version_of() {
	local name
	name=$(basename "$1")
	[[ $name =~ ^Libero_SoC_([0-9][0-9.]*[0-9])_online_lin\.bin$ ]] ||
		die "cannot tell the Libero version from the name $name (expected Libero_SoC_<version>_online_lin.bin)"
	echo "${BASH_REMATCH[1]}"
}

