#!/usr/bin/env bats
# seam-α: fake HOME — no network, no root required

load '../helpers/common'

SCRIPT="${PROVISION_ROOT}/user/40-mise-config.sh"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR

	FAKE_HOME="${TMPDIR}/home"
	mkdir --parents "${FAKE_HOME}"
	export HOME="${FAKE_HOME}"
}

teardown() {
	rm --recursive --force "${TMPDIR}"
}

@test "mise_config_toml_deployed_with_0644_mode_when_home_is_empty" {
	run bash "${SCRIPT}"
	assert_success
	run stat --format='%a' "${FAKE_HOME}/.config/mise/config.toml"
	assert_output "644"
}

@test "mise_config_toml_overwrites_cleanly_when_rerun_byte_identical" {
	run bash "${SCRIPT}"
	assert_success
	hash1="$(md5sum "${FAKE_HOME}/.config/mise/config.toml" | awk '{print $1}')"
	run bash "${SCRIPT}"
	assert_success
	hash2="$(md5sum "${FAKE_HOME}/.config/mise/config.toml" | awk '{print $1}')"
	[ "${hash1}" = "${hash2}" ]
}
