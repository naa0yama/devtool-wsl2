#!/usr/bin/env bats
# Tests for cleanup_mounts in provision-chroot.sh (seam-3: idempotent ERR/EXIT trap)
bats_require_minimum_version 1.5.0

load '../helpers/common'

PROVISION_CHROOT_SH="${BATS_TEST_DIRNAME}/../../scripts/image/provision-chroot.sh"

_require_sudo() {
	if ! sudo --non-interactive true 2>/dev/null; then
		skip "requires sudo"
	fi
}

# Bind mount setup helper — same fixture as qcow2-provision-chroot.bats (Cycle 2)
_setup_mounts() {
	local mnt="$1"
	sudo touch "${mnt}/run/systemd/resolve/stub-resolv.conf"
	sudo mount --bind /run/systemd/resolve/stub-resolv.conf \
		"${mnt}/run/systemd/resolve/stub-resolv.conf"
	sudo mount --bind /dev "${mnt}/dev"
	sudo mount --bind /proc "${mnt}/proc"
	sudo mount --bind /sys "${mnt}/sys"
	sudo mount --bind /dev/pts "${mnt}/dev/pts"
}

setup() {
	_require_sudo
	MNT=$(mktemp --directory)
	mkdir -p "${MNT}/dev/pts" "${MNT}/proc" "${MNT}/sys" "${MNT}/etc" \
		"${MNT}/run/systemd/resolve"
	ln -s ../run/systemd/resolve/stub-resolv.conf "${MNT}/etc/resolv.conf"

	_HOST_STUB_CREATED=0
	if [[ ! -f /run/systemd/resolve/stub-resolv.conf ]]; then
		sudo mkdir -p /run/systemd/resolve
		sudo touch /run/systemd/resolve/stub-resolv.conf
		_HOST_STUB_CREATED=1
	fi
}

teardown() {
	for m in \
		"${MNT}/dev/pts" \
		"${MNT}/dev" \
		"${MNT}/proc" \
		"${MNT}/sys" \
		"${MNT}/run/systemd/resolve/stub-resolv.conf"; do
		mountpoint -q "${m}" 2>/dev/null && sudo umount "${m}" || true
	done
	rm -rf "${MNT}"

	if [[ "${_HOST_STUB_CREATED:-0}" -eq 1 ]]; then
		sudo rm -f /run/systemd/resolve/stub-resolv.conf
		sudo rmdir --ignore-fail-on-non-empty /run/systemd/resolve 2>/dev/null || true
	fi
}

@test "cleanup_mounts_unmounts_all_binds_when_called_once" {
	_setup_mounts "${MNT}"
	sudo bash -c "source '${PROVISION_CHROOT_SH}' && cleanup_mounts '${MNT}'"
	run ! mountpoint -q "${MNT}/dev" 2>/dev/null
	run ! mountpoint -q "${MNT}/proc" 2>/dev/null
	run ! mountpoint -q "${MNT}/sys" 2>/dev/null
	run ! mountpoint -q "${MNT}/dev/pts" 2>/dev/null
	run ! mountpoint -q "${MNT}/run/systemd/resolve/stub-resolv.conf" 2>/dev/null
}

@test "cleanup_mounts_is_idempotent_when_called_twice" {
	_setup_mounts "${MNT}"
	sudo bash -c "set -e; source '${PROVISION_CHROOT_SH}' && cleanup_mounts '${MNT}' && cleanup_mounts '${MNT}'"
}

@test "cleanup_mounts_runs_on_err_trap_when_provision_fails" {
	# --force-fail=post-bind-dev injects an error after all bind mounts are active
	run sudo "${PROVISION_CHROOT_SH}" --force-fail=post-bind-dev "${MNT}" /tmp/dummy_scripts
	# Script must exit non-zero (ERR trap fired)
	[ "${status}" -ne 0 ]
	# ERR trap must have fired cleanup_mounts — all mounts removed
	run ! mountpoint -q "${MNT}/dev" 2>/dev/null
	run ! mountpoint -q "${MNT}/proc" 2>/dev/null
	run ! mountpoint -q "${MNT}/sys" 2>/dev/null
	run ! mountpoint -q "${MNT}/dev/pts" 2>/dev/null
	run ! mountpoint -q "${MNT}/run/systemd/resolve/stub-resolv.conf" 2>/dev/null
}

@test "cleanup_mounts_removes_stub_touch_file_but_keeps_symlink_intact" {
	_setup_mounts "${MNT}"
	sudo bash -c "source '${PROVISION_CHROOT_SH}' && cleanup_mounts '${MNT}'"
	# symlink target string must be unchanged after cleanup
	run readlink "${MNT}/etc/resolv.conf"
	assert_success
	assert_output "../run/systemd/resolve/stub-resolv.conf"
	# stub touch file must be removed
	[ ! -f "${MNT}/run/systemd/resolve/stub-resolv.conf" ]
}
