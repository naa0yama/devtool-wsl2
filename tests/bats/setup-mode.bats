#!/usr/bin/env bats
# Tests for detect_setup_mode in scripts/bin/setup.sh

load '../helpers/common'

SETUP_SH="${BATS_TEST_DIRNAME}/../../scripts/bin/setup.sh"

_source_setup() {
	# shellcheck source=/dev/null
	source "${SETUP_SH}"
}

@test "detect_setup_mode returns wsl2 when DEVTOOL_SETUP_MODE=wsl2" {
	export DEVTOOL_SETUP_MODE=wsl2
	_source_setup
	run detect_setup_mode
	assert_success
	assert_output "wsl2"
}

@test "detect_setup_mode returns vm when DEVTOOL_SETUP_MODE=vm" {
	export DEVTOOL_SETUP_MODE=vm
	_source_setup
	run detect_setup_mode
	assert_success
	assert_output "vm"
}

@test "detect_setup_mode returns remote when DEVTOOL_SETUP_MODE=remote" {
	export DEVTOOL_SETUP_MODE=remote
	_source_setup
	run detect_setup_mode
	assert_success
	assert_output "remote"
}

@test "detect_setup_mode honors arbitrary override value" {
	export DEVTOOL_SETUP_MODE=custom-value
	_source_setup
	run detect_setup_mode
	assert_success
	assert_output "custom-value"
}

@test "setup.sh does not execute main when sourced" {
	unset DEVTOOL_SETUP_MODE
	run bash -c "source '${SETUP_SH}' 2>&1; echo SOURCED_OK"
	assert_success
	assert_line --index -1 "SOURCED_OK"
}
