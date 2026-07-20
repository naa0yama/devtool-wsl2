#!/usr/bin/env bats
# Tests for scripts/provision/system/15-user.sh

load '../helpers/common'

SCRIPT="${PROVISION_ROOT}/system/15-user.sh"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR

	FAKE_BIN="${TMPDIR}/bin"
	mkdir -p "${FAKE_BIN}"

	# groupadd stub: no-op (gid idempotency guard makes real call unnecessary)
	printf '#!/bin/sh\nexit 0\n' > "${FAKE_BIN}/groupadd"
	chmod +x "${FAKE_BIN}/groupadd"

	# useradd stub: record args to ${TMPDIR}/useradd.log (TMPDIR is exported)
	printf '#!/bin/sh\necho "$@" >> "${TMPDIR}/useradd.log"\nexit 0\n' \
		> "${FAKE_BIN}/useradd"
	chmod +x "${FAKE_BIN}/useradd"

	# getent stub: user/group not found (exit 1) — allows script to call useradd/groupadd
	printf '#!/bin/sh\nexit 1\n' > "${FAKE_BIN}/getent"
	chmod +x "${FAKE_BIN}/getent"

	# chpasswd stub: drain stdin, exit 0
	printf '#!/bin/sh\ncat > /dev/null\nexit 0\n' > "${FAKE_BIN}/chpasswd"
	chmod +x "${FAKE_BIN}/chpasswd"

	# passwd stub: exit 0
	printf '#!/bin/sh\nexit 0\n' > "${FAKE_BIN}/passwd"
	chmod +x "${FAKE_BIN}/passwd"

	export PATH="${FAKE_BIN}:${PATH}"

	FAKE_ROOT="${TMPDIR}/root"
	mkdir -p "${FAKE_ROOT}/etc/sudoers.d"
	export PROVISION_CHROOT="${FAKE_ROOT}"
}

teardown() {
	rm --recursive --force "${TMPDIR}"
}

@test "useradd_called_with_fish_shell_when_devtool_user_shell_unset" {
	unset DEVTOOL_USER_SHELL
	run bash "${SCRIPT}"
	assert_success
	run grep -- '--shell /usr/bin/fish' "${TMPDIR}/useradd.log"
	assert_success
}

@test "useradd_called_with_bash_shell_when_devtool_user_shell_set_to_bash" {
	export DEVTOOL_USER_SHELL=/bin/bash
	run bash "${SCRIPT}"
	assert_success
	run grep -- '--shell /bin/bash' "${TMPDIR}/useradd.log"
	assert_success
}

@test "useradd_called_with_uid_1100_and_gid_1100_when_user_missing" {
	run bash "${SCRIPT}"
	assert_success
	run grep -- '--uid 1100' "${TMPDIR}/useradd.log"
	assert_success
	run grep -- '--gid 1100' "${TMPDIR}/useradd.log"
	assert_success
}

@test "sudoers_file_has_0440_permissions_when_created" {
	run bash "${SCRIPT}"
	assert_success
	run test -f "${PROVISION_CHROOT}/etc/sudoers.d/user"
	assert_success
	run stat --format="%a" "${PROVISION_CHROOT}/etc/sudoers.d/user"
	assert_success
	assert_output "440"
}

@test "useradd_not_called_when_user_already_exists" {
	# Override getent stub to indicate user/group already exist
	printf '#!/bin/sh\nexit 0\n' > "${FAKE_BIN}/getent"
	run bash "${SCRIPT}"
	assert_success
	[ ! -f "${TMPDIR}/useradd.log" ]
}
