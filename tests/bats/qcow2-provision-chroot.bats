#!/usr/bin/env bats
# Tests for scripts/image/provision-chroot.sh (seam-2: bind mount + dry-run)
bats_require_minimum_version 1.5.0

load '../helpers/common'

PROVISION_CHROOT_SH="${BATS_TEST_DIRNAME}/../../scripts/image/provision-chroot.sh"

_require_sudo() {
	if ! sudo --non-interactive true 2>/dev/null; then
		skip "requires sudo"
	fi
}

setup() {
	_require_sudo
	MNT=$(mktemp --directory)
	mkdir -p "${MNT}/dev/pts" "${MNT}/proc" "${MNT}/sys" "${MNT}/etc" \
		"${MNT}/run/systemd/resolve"
	ln -s ../run/systemd/resolve/stub-resolv.conf "${MNT}/etc/resolv.conf"

	# Create host resolver stub if absent (WSL2 lacks systemd-resolved)
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

@test "provision_chroot_exits_cleanly_and_unmounts_when_dry_run" {
	run sudo "${PROVISION_CHROOT_SH}" --dry-run "${MNT}" /tmp/dummy_scripts
	assert_success
	run ! mountpoint -q "${MNT}/dev" 2>/dev/null
	run ! mountpoint -q "${MNT}/proc" 2>/dev/null
	run ! mountpoint -q "${MNT}/sys" 2>/dev/null
	run ! mountpoint -q "${MNT}/dev/pts" 2>/dev/null
	run ! mountpoint -q "${MNT}/run/systemd/resolve/stub-resolv.conf" 2>/dev/null
}

@test "provision_chroot_preserves_resolv_symlink_when_dry_run" {
	sudo "${PROVISION_CHROOT_SH}" --dry-run "${MNT}" /tmp/dummy_scripts
	run readlink "${MNT}/etc/resolv.conf"
	assert_success
	assert_output "../run/systemd/resolve/stub-resolv.conf"
}

# Helper: copy bash + touch + dynamic dependencies into MNT for chroot tests.
# Pre-creates /opt/marker so dummy scripts need only touch (not mkdir).
_setup_chroot_rootfs() {
	local mnt="$1"
	mkdir -p "${mnt}/bin" "${mnt}/usr/bin" \
		"${mnt}/lib/x86_64-linux-gnu" "${mnt}/lib64" \
		"${mnt}/opt/marker"
	sudo cp /bin/bash "${mnt}/bin/bash"
	sudo ln -sf bash "${mnt}/bin/sh"
	sudo cp /usr/bin/env "${mnt}/usr/bin/env"
	sudo cp /bin/touch "${mnt}/bin/touch"
	sudo cp /lib/x86_64-linux-gnu/libc.so.6 "${mnt}/lib/x86_64-linux-gnu/"
	sudo cp /lib/x86_64-linux-gnu/libtinfo.so.6 "${mnt}/lib/x86_64-linux-gnu/"
	sudo cp /lib64/ld-linux-x86-64.so.2 "${mnt}/lib64/"
}

@test "provision_chroot_executes_bootstrap_in_chroot_when_not_dry_run" {
	[[ -x /bin/bash ]] || skip "no /bin/bash for chroot fixture"
	[[ -f /lib/x86_64-linux-gnu/libtinfo.so.6 ]] || skip "missing libtinfo.so.6 for chroot fixture"

	_setup_chroot_rootfs "${MNT}"

	SCRIPTS_SRC=$(mktemp --directory)
	mkdir -p "${SCRIPTS_SRC}/provision" "${SCRIPTS_SRC}/image"
	printf '#!/bin/sh\ntouch /opt/marker/bootstrap-ran\n' \
		> "${SCRIPTS_SRC}/provision/bootstrap.sh"
	printf '#!/bin/sh\ntouch /opt/marker/finalize-ran\n' \
		> "${SCRIPTS_SRC}/image/finalize.sh"
	chmod +x "${SCRIPTS_SRC}/provision/bootstrap.sh" \
		"${SCRIPTS_SRC}/image/finalize.sh"

	run sudo "${PROVISION_CHROOT_SH}" "${MNT}" "${SCRIPTS_SRC}"
	assert_success

	[[ -f "${MNT}/opt/marker/bootstrap-ran" ]]
	[[ -f "${MNT}/opt/marker/finalize-ran" ]]

	run readlink "${MNT}/etc/resolv.conf"
	assert_success
	assert_output "../run/systemd/resolve/stub-resolv.conf"

	run ! mountpoint -q "${MNT}/dev" 2>/dev/null
	run ! mountpoint -q "${MNT}/proc" 2>/dev/null
	run ! mountpoint -q "${MNT}/sys" 2>/dev/null
	run ! mountpoint -q "${MNT}/dev/pts" 2>/dev/null
	run ! mountpoint -q "${MNT}/run/systemd/resolve/stub-resolv.conf" 2>/dev/null

	rm -rf "${SCRIPTS_SRC}"
}

@test "provision_chroot_aborts_when_resolv_symlink_is_broken" {
	rm "${MNT}/etc/resolv.conf"
	touch "${MNT}/etc/resolv.conf"

	run sudo "${PROVISION_CHROOT_SH}" "${MNT}" /tmp/dummy_scripts
	[ "${status}" -ne 0 ]
	[[ "${output}" =~ resolv.conf ]]
}
