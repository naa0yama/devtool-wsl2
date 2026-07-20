#!/usr/bin/env bash
set -euo pipefail

# Bind mount targets: host_src:guest_relative_dst (mount order)
BIND_TARGETS=(
	"/dev:dev"
	"/proc:proc"
	"/sys:sys"
	"/dev/pts:dev/pts"
)

cleanup_mounts() {
	local mnt="$1"
	# WHY-NOT: reverse loop over BIND_TARGETS — /dev/pts must precede /dev (nested);
	#   explicit list makes the required order unambiguous without array arithmetic
	for m in "${mnt}/dev/pts" "${mnt}/dev" "${mnt}/proc" "${mnt}/sys" \
	         "${mnt}/run/systemd/resolve/stub-resolv.conf"; do
		mountpoint -q "${m}" 2>/dev/null && umount "${m}" || true
	done
	rm -f "${mnt}/run/systemd/resolve/stub-resolv.conf" 2>/dev/null || true
	rmdir --ignore-fail-on-non-empty \
		"${mnt}/run/systemd/resolve" "${mnt}/run/systemd" 2>/dev/null || true
}

# Allow sourcing for unit tests without executing main body
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

FORCE_FAIL=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--force-fail=*) FORCE_FAIL="${1#--force-fail=}"; shift ;;
		--) shift; break ;;
		*) break ;;
	esac
done

MNT="${1:?mount root required}"
# shellcheck disable=SC2034
# WHY-NOT: remove param — cycle-4 chroot exec will use SCRIPTS_SRC
SCRIPTS_SRC="${2:?scripts source dir required}"

trap 'cleanup_mounts "${MNT}"' ERR EXIT

# resolv.conf stub: bind host resolver stub into guest without modifying symlink
mkdir -p "${MNT}/run/systemd/resolve"
touch "${MNT}/run/systemd/resolve/stub-resolv.conf"
mount --bind /run/systemd/resolve/stub-resolv.conf \
	"${MNT}/run/systemd/resolve/stub-resolv.conf"

[[ "${FORCE_FAIL}" == "post-bind-resolv" ]] && { echo "forced failure: post-bind-resolv" >&2; exit 1; }

for entry in "${BIND_TARGETS[@]}"; do
	src="${entry%%:*}"
	dst="${MNT}/${entry##*:}"
	mount --bind "${src}" "${dst}"
done

[[ "${FORCE_FAIL}" == "post-bind-dev" ]] && { echo "forced failure: post-bind-dev" >&2; exit 1; }

if [[ "${DRY_RUN}" -eq 1 ]]; then
	# WHY-NOT: chroot exec skipped in --dry-run; added in Cycle 4
	exit 0
fi

# TODO(cycle-4): chroot exec
# chroot "${MNT}" env DEVTOOL_ENV=vm bash /opt/devtool/scripts/provision/bootstrap.sh
