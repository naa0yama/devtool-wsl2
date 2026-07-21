#!/usr/bin/env bats
# seam-β: runs inside ubuntu:24.04 container; needs docker daemon on host

load '../helpers/common'

SCRIPT="${PROVISION_ROOT}/system/40-cleanup-ubuntu.sh"

setup_file() {
	docker info &>/dev/null || return 0

	CONTAINER_VM=$(docker run --detach ubuntu:24.04 sleep infinity)
	echo "${CONTAINER_VM}" > "${BATS_FILE_TMPDIR}/container_vm_id"
	docker cp "${SCRIPT}" "${CONTAINER_VM}:/tmp/40-cleanup-ubuntu.sh"
	docker exec --env DEVTOOL_ENV=vm "${CONTAINER_VM}" bash /tmp/40-cleanup-ubuntu.sh

	CONTAINER_WSL=$(docker run --detach ubuntu:24.04 sleep infinity)
	echo "${CONTAINER_WSL}" > "${BATS_FILE_TMPDIR}/container_wsl_id"
	docker cp "${SCRIPT}" "${CONTAINER_WSL}:/tmp/40-cleanup-ubuntu.sh"
	docker exec --env DEVTOOL_ENV=wsl "${CONTAINER_WSL}" bash /tmp/40-cleanup-ubuntu.sh
}

teardown_file() {
	for id_file in container_vm_id container_wsl_id; do
		CONTAINER=$(cat "${BATS_FILE_TMPDIR}/${id_file}" 2>/dev/null) || continue
		docker rm --force "${CONTAINER}" > /dev/null 2>&1 || true
	done
}

@test "ubuntu_user_deleted_when_devtool_env_is_vm" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_vm_id")
	run docker exec "${CONTAINER}" id ubuntu
	assert_failure
}

@test "home_ubuntu_removed_when_devtool_env_is_vm" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_vm_id")
	run docker exec "${CONTAINER}" test -d /home/ubuntu
	assert_failure
}

@test "ubuntu_user_preserved_when_devtool_env_is_wsl" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_wsl_id")
	run docker exec "${CONTAINER}" id ubuntu
	assert_success
}

@test "script_exits_zero_on_second_run_when_devtool_env_is_vm" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_vm_id")
	run docker exec --env DEVTOOL_ENV=vm "${CONTAINER}" bash /tmp/40-cleanup-ubuntu.sh
	assert_success
}
