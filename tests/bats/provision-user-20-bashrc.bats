#!/usr/bin/env bats
# seam-α: fake HOME — no network, no root required

load '../helpers/common'

SCRIPT="${PROVISION_ROOT}/user/20-bashrc.sh"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR

	FAKE_HOME="${TMPDIR}/home"
	mkdir -p "${FAKE_HOME}"
	export HOME="${FAKE_HOME}"
}

teardown() {
	rm --recursive --force "${TMPDIR}"
}

@test "bashrc_deployed_with_0644_mode_when_home_is_empty" {
	run bash "${SCRIPT}"
	assert_success
	run stat --format='%a' "${FAKE_HOME}/.bashrc"
	assert_output "644"
}

@test "bashrc_overwrites_cleanly_when_rerun_byte_identical" {
	run bash "${SCRIPT}"
	assert_success
	hash1="$(md5sum "${FAKE_HOME}/.bashrc" | awk '{print $1}')"
	run bash "${SCRIPT}"
	assert_success
	hash2="$(md5sum "${FAKE_HOME}/.bashrc" | awk '{print $1}')"
	[ "${hash1}" = "${hash2}" ]
}
