#!/usr/bin/env bats
# seam-β: runs inside ubuntu:24.04 container; needs docker daemon on host

load '../helpers/common'

SCRIPT="${PROVISION_ROOT}/system/20-docker-engine.sh"

setup_file() {
	CONTAINER=$(docker run --detach ubuntu:24.04 sleep infinity)
	echo "${CONTAINER}" > "${BATS_FILE_TMPDIR}/container_id"

	# curl and ca-certificates are required by the provision script
	docker exec "${CONTAINER}" \
		bash -c "apt-get update -qq && apt-get install --yes --no-install-recommends curl ca-certificates"

	# Cycle 1 prerequisite: user with uid/gid 1100 must exist before docker group assignment
	docker exec "${CONTAINER}" groupadd --gid 1100 user
	docker exec "${CONTAINER}" useradd --create-home --uid 1100 --gid 1100 user

	docker cp "${SCRIPT}" "${CONTAINER}:/tmp/20-docker-engine.sh"
	docker exec "${CONTAINER}" bash /tmp/20-docker-engine.sh
}

teardown_file() {
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id" 2>/dev/null) || return 0
	docker rm --force "${CONTAINER}" > /dev/null 2>&1 || true
}

@test "docker_list_exists_when_script_runs_in_container" {
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" test -f /etc/apt/sources.list.d/docker.list
	assert_success
}

@test "docker_ce_installed_when_script_runs_in_container" {
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" dpkg --status docker-ce
	assert_success
}

@test "user_in_docker_group_when_script_runs_in_container" {
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" bash -c 'id --name --groups user | tr " " "\n" | grep --fixed-strings --line-regexp docker'
	assert_success
}

@test "script_exits_zero_when_run_again_idempotent" {
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" bash /tmp/20-docker-engine.sh
	assert_success
}
