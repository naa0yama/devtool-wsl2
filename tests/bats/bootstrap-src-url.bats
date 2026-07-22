#!/usr/bin/env bats
# seam: DEVTOOL_SRC_URL — full source-archive URL override for main() fetch

load '../helpers/common'

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/provision/bootstrap.sh"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR

	# Existing self file skips the self-download block so dispatch reaches main()
	local self_file="${TMPDIR}/bootstrap.sh"
	printf '#!/bin/sh\n' > "${self_file}"
	chmod +x "${self_file}"
	export DEVTOOL_BOOTSTRAP_SELF="${self_file}"

	export DEVTOOL_CACHE="${TMPDIR}/cache"
	export DRY_RUN=1
	export DEVTOOL_ENV=bare
}

teardown() {
	rm --recursive --force "${TMPDIR}"
}

@test "fetch_url_uses_override_when_devtool_src_url_set" {
	export DEVTOOL_SRC_URL="http://192.0.2.10/devtool-src.tar.gz"
	run bash "${SCRIPT}"
	assert_success
	assert_output --partial "Fetching tarball: http://192.0.2.10/devtool-src.tar.gz"
}

@test "fetch_url_uses_github_archive_when_devtool_src_url_unset" {
	run bash "${SCRIPT}"
	assert_success
	assert_output --partial "Fetching tarball: https://github.com/naa0yama/devtool-wsl2/archive/main.tar.gz"
}
