#!/usr/bin/env bash
set -euxo pipefail

MNT="${1:?Usage: provision-chroot.sh <MNT_PATH> <SCRIPTS_ROOT>}"
SCRIPTS_ROOT="${2:?Usage: provision-chroot.sh <MNT_PATH> <SCRIPTS_ROOT>}"
# PROVISION_DIR: host-side path for script iteration (MNT-prefixed)
PROVISION_DIR="${MNT}${SCRIPTS_ROOT}/provision"
# PROVISION_ROOT: chroot-internal path passed via env to provisioning scripts
# WHY-NOT: BASH_SOURCE[0] 依存 — chroot stdin 経由で空になり fallback で / になるため env 明示が確実
PROVISION_ROOT="${SCRIPTS_ROOT}/provision"

log_info() { echo "[INFO] $*"; }

_cleanup() {
	for mp in /dev/pts /dev /proc /sys; do
		if mountpoint --quiet "${MNT}${mp}" 2>/dev/null; then
			umount --lazy "${MNT}${mp}" || true
		fi
	done
}
trap _cleanup EXIT ERR

# bind mounts needed by scripts running inside chroot
for mp in /dev /dev/pts /proc /sys; do
	mount --bind "${mp}" "${MNT}${mp}"
done

export DEVTOOL_ENV="vm"
export PROVISION_ROOT

# Phase 1: system scripts run as root (uid=0) inside chroot
log_info "Phase 1: system provisioning"
for f in "${PROVISION_DIR}/system/"*.sh; do
	log_info "  running system: ${f##*/}"
	chroot "${MNT}" env PROVISION_ROOT="${PROVISION_ROOT}" DEVTOOL_ENV="${DEVTOOL_ENV}" bash < "${f}"
done

# Phase 2: user scripts run as uid=1100 inside chroot
# WHY-NOT: bash <(cat f) — sudo closefrom(3) closes the process substitution fd
log_info "Phase 2: user provisioning"
for f in "${PROVISION_DIR}/user/"*.sh; do
	log_info "  running user: ${f##*/}"
	chroot "${MNT}" sudo --preserve-env=PROVISION_ROOT,DEVTOOL_ENV --user=user bash < "${f}"
done

log_info "provision-chroot.sh complete"
