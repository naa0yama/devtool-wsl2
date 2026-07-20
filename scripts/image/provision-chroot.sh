#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--) shift; break ;;
		*) break ;;
	esac
done

MNT="${1:?mount root required}"
# shellcheck disable=SC2034
# WHY-NOT: remove param — cycle-4 chroot exec will use SCRIPTS_SRC
SCRIPTS_SRC="${2:?scripts source dir required}"

# WHY-NOT: cleanup trap deferred to Cycle 3 — idempotency verification added there;
#   bats teardown() handles unmount in this cycle

# Bind mount targets: "host_src:guest_relative_dst"
BIND_TARGETS=(
	"/dev:dev"
	"/proc:proc"
	"/sys:sys"
	"/dev/pts:dev/pts"
)

# resolv.conf stub: bind host resolver stub into guest without modifying symlink
mkdir -p "${MNT}/run/systemd/resolve"
touch "${MNT}/run/systemd/resolve/stub-resolv.conf"
mount --bind /run/systemd/resolve/stub-resolv.conf \
	"${MNT}/run/systemd/resolve/stub-resolv.conf"

for entry in "${BIND_TARGETS[@]}"; do
	src="${entry%%:*}"
	dst="${MNT}/${entry##*:}"
	mount --bind "${src}" "${dst}"
done

if [[ "${DRY_RUN}" -eq 1 ]]; then
	# WHY-NOT: chroot exec skipped in --dry-run; added in Cycle 4
	exit 0
fi

# TODO(cycle-4): chroot exec
# chroot "${MNT}" env DEVTOOL_ENV=vm bash /opt/devtool/scripts/provision/bootstrap.sh
