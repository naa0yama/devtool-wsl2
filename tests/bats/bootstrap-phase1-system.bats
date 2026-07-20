#!/usr/bin/env bats
# seam-β: runs inside ubuntu:24.04 container; needs docker daemon on host

load '../helpers/common'

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/provision/bootstrap.sh"

setup_file() {
	docker info &>/dev/null || return 0

	CONTAINER=$(docker run --detach --privileged ubuntu:24.04 sleep infinity)
	echo "${CONTAINER}" > "${BATS_FILE_TMPDIR}/container_id"

	docker exec "${CONTAINER}" apt-get update -qq
	docker exec "${CONTAINER}" apt-get install --yes --no-install-recommends sudo

	# No-tty for sudo in non-interactive docker exec
	docker exec "${CONTAINER}" bash -c \
		"printf 'Defaults !requiretty\n' > /etc/sudoers.d/notty"

	# Non-root user for root guard test (uid=1101, separate from DEFAULT_USERNAME=user)
	docker exec "${CONTAINER}" useradd --uid 1101 --create-home --shell /bin/bash tester

	# Mock provision dir
	docker exec "${CONTAINER}" mkdir -p \
		/tmp/devtool-provision/system \
		/tmp/devtool-provision/user

	# 15-user.sh mock: log DEVTOOL_USER_SHELL and create user
	docker exec "${CONTAINER}" bash -c \
		'cat > /tmp/devtool-provision/system/15-user.sh << '"'"'SCRIPT'"'"'
#!/usr/bin/env bash
set -euo pipefail
echo "15-user:DEVTOOL_USER_SHELL=${DEVTOOL_USER_SHELL:-}" >> /tmp/phase1.log
useradd --shell "${DEVTOOL_USER_SHELL:-/bin/bash}" --uid 1100 --create-home user 2>/dev/null || true
SCRIPT
chmod +x /tmp/devtool-provision/system/15-user.sh'

	# 20-docker-engine.sh mock: log invocation only (no actual install)
	docker exec "${CONTAINER}" bash -c \
		'cat > /tmp/devtool-provision/system/20-docker-engine.sh << '"'"'SCRIPT'"'"'
#!/usr/bin/env bash
echo "20-docker-engine:called" >> /tmp/phase1.log
SCRIPT
chmod +x /tmp/devtool-provision/system/20-docker-engine.sh'

	# Phase 2 stub: log re-exec env and exit (replaces bootstrap.sh for re-exec)
	docker exec "${CONTAINER}" bash -c \
		'cat > /tmp/phase2-stub.sh << '"'"'SCRIPT'"'"'
#!/usr/bin/env bash
echo "DEVTOOL_BOOTSTRAP_PHASE=${DEVTOOL_BOOTSTRAP_PHASE:-}" >> /tmp/phase1-reexec.log
echo "DEVTOOL_PROVISION_DIR=${DEVTOOL_PROVISION_DIR:-}" >> /tmp/phase1-reexec.log
echo "EUID=${EUID}" >> /tmp/phase1-reexec.log
SCRIPT
chmod +x /tmp/phase2-stub.sh'

	# Pre-create reexec log as world-writable (user uid=1100 writes it after re-exec)
	docker exec "${CONTAINER}" install -m 0666 /dev/null /tmp/phase1-reexec.log

	docker cp "${SCRIPT}" "${CONTAINER}:/bootstrap.sh"

	# Run phase 1 as root; phase2-stub intercepts re-exec
	docker exec "${CONTAINER}" bash -c \
		"DEVTOOL_BOOTSTRAP_PHASE=1 \
		 DEVTOOL_PROVISION_DIR=/tmp/devtool-provision \
		 DEVTOOL_BOOTSTRAP_SELF=/tmp/phase2-stub.sh \
		 DEVTOOL_SKIP_PROVISION_FETCH=1 \
		 DEFAULT_USERNAME=user \
		 bash /bootstrap.sh" || true
}

teardown_file() {
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id" 2>/dev/null) || return 0
	docker rm --force "${CONTAINER}" > /dev/null 2>&1 || true
}

@test "phase1_exits_1_when_not_root" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec --user tester "${CONTAINER}" bash -c \
		"DEVTOOL_BOOTSTRAP_PHASE=1 \
		 DEVTOOL_PROVISION_DIR=/tmp/devtool-provision \
		 DEVTOOL_BOOTSTRAP_SELF=/tmp/phase2-stub.sh \
		 DEVTOOL_SKIP_PROVISION_FETCH=1 \
		 bash /bootstrap.sh"
	assert_equal "${status}" 1
}

@test "phase1_calls_15user_with_bash_shell_when_devtool_user_shell_set" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" grep '15-user:DEVTOOL_USER_SHELL=/bin/bash' /tmp/phase1.log
	assert_success
}

@test "phase1_calls_20docker_engine_when_phase1_runs" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" grep '20-docker-engine:called' /tmp/phase1.log
	assert_success
}

@test "phase1_reexecs_phase2_with_provision_dir_when_phase1_completes" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" grep 'DEVTOOL_BOOTSTRAP_PHASE=2' /tmp/phase1-reexec.log
	assert_success
	run docker exec "${CONTAINER}" grep 'DEVTOOL_PROVISION_DIR=/tmp/devtool-provision' /tmp/phase1-reexec.log
	assert_success
}
