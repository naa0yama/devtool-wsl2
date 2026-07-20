#!/usr/bin/env bats
# Static checks for Dockerfile — grep-based provision layout inspection

load '../helpers/common'

DOCKERFILE="${BATS_TEST_DIRNAME}/../../Dockerfile"

@test "dockerfile_loops_over_system_scripts_when_base_layer_built" {
	run grep --fixed-strings 'for f in /opt/devtool/scripts/provision/system/*.sh' "${DOCKERFILE}"
	assert_success
}

@test "dockerfile_loops_over_user_scripts_when_user_layer_built" {
	run grep --fixed-strings 'for f in /opt/devtool/scripts/provision/user/*.sh' "${DOCKERFILE}"
	assert_success
}

@test "dockerfile_removes_stale_50_user_reference" {
	run grep --fixed-strings '50-user.sh' "${DOCKERFILE}"
	assert_failure
}

@test "dockerfile_removes_stale_30_mise_reference" {
	run grep --fixed-strings '30-mise.sh' "${DOCKERFILE}"
	assert_failure
}

@test "dockerfile_removes_stale_40_fish_reference" {
	# 40-fish.sh は個別 RUN 参照を削除; ループ経由で実行されるが直参照は不要
	run grep --regexp '/opt/devtool/provision/system/40-fish\.sh' "${DOCKERFILE}"
	assert_failure
}

@test "dockerfile_sets_devtool_env_wsl2_in_system_and_user_loops" {
	run grep --count 'DEVTOOL_ENV=wsl2' "${DOCKERFILE}"
	assert_success
	[[ "${output}" -ge 2 ]]
}
