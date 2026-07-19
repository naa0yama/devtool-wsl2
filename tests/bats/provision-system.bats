#!/usr/bin/env bats
# Tests for scripts/provision/system/*.sh

load '../helpers/common'

SYSTEM_DIR="${PROVISION_ROOT}/system"

@test "system scripts have valid shebang" {
	for script in "${SYSTEM_DIR}"/*.sh; do
		run head -1 "${script}"
		assert_success
		assert_output '#!/usr/bin/env bash'
	done
}

@test "system scripts are executable" {
	for script in "${SYSTEM_DIR}"/*.sh; do
		run test -x "${script}"
		assert_success
	done
}

@test "system scripts pass shellcheck" {
	for script in "${SYSTEM_DIR}"/*.sh; do
		run shellcheck "${script}"
		assert_success
	done
}

@test "10-apt-base runs idempotently with DRY_RUN" {
	run env DRY_RUN=1 "${SYSTEM_DIR}/10-apt-base.sh"
	assert_success
	run env DRY_RUN=1 "${SYSTEM_DIR}/10-apt-base.sh"
	assert_success
}

@test "60-wsl-conf skips wsl.conf when DEVTOOL_ENV is not wsl2" {
	run env DRY_RUN=1 DEVTOOL_ENV=vm "${SYSTEM_DIR}/60-wsl-conf.sh"
	assert_success
	assert_output --partial "skipping /etc/wsl.conf"
}
