#!/usr/bin/env bats
# seam-α: fake HOME — no network, no root required

load '../helpers/common'

SCRIPT="${PROVISION_ROOT}/user/30-fish-config.sh"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR

	FAKE_HOME="${TMPDIR}/home"
	mkdir --parents "${FAKE_HOME}/.config/fish/functions"
	# Pre-create fisher.fish stub to skip network download
	touch "${FAKE_HOME}/.config/fish/functions/fisher.fish"
	export HOME="${FAKE_HOME}"
}

teardown() {
	rm --recursive --force "${TMPDIR}"
}

@test "config_fish_deployed_with_0644_mode_when_home_is_empty" {
	run bash "${SCRIPT}"
	assert_success
	run stat --format='%a' "${FAKE_HOME}/.config/fish/config.fish"
	assert_output "644"
}

@test "config_fish_overwrites_cleanly_when_rerun_byte_identical" {
	run bash "${SCRIPT}"
	assert_success
	hash1="$(md5sum "${FAKE_HOME}/.config/fish/config.fish" | awk '{print $1}')"
	run bash "${SCRIPT}"
	assert_success
	hash2="$(md5sum "${FAKE_HOME}/.config/fish/config.fish" | awk '{print $1}')"
	[ "${hash1}" = "${hash2}" ]
}

@test "fish_prompt_deployed_with_0644_mode_when_home_is_empty" {
	run bash "${SCRIPT}"
	assert_success
	run stat --format='%a' "${FAKE_HOME}/.config/fish/functions/fish_prompt.fish"
	assert_output "644"
}
