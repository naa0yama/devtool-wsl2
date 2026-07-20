#!/usr/bin/env bats
# seam-β: runs inside ubuntu:24.04 container; needs docker daemon on host

load '../helpers/common'

SCRIPT_SH="${BATS_TEST_DIRNAME}/../../scripts/image/provision-chroot.sh"

setup_file() {
	docker info &>/dev/null || return 0

	CONTAINER=$(docker run --detach --privileged ubuntu:24.04 sleep infinity)
	echo "${CONTAINER}" > "${BATS_FILE_TMPDIR}/container_id"

	docker exec "${CONTAINER}" apt-get update -qq
	docker exec "${CONTAINER}" apt-get install --yes --no-install-recommends sudo
	docker exec "${CONTAINER}" useradd --uid 1100 --create-home --shell /bin/bash user
	docker exec "${CONTAINER}" bash -c \
		"printf 'user ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/user"
	docker exec "${CONTAINER}" bash -c \
		"printf 'Defaults !requiretty\n' > /etc/sudoers.d/notty"

	# chroot stub: drop MNT_PATH arg, exec remaining command in-place
	docker exec "${CONTAINER}" bash -c \
		'printf "#!/usr/bin/env bash\nshift\nexec \"\$@\"\n" > /usr/sbin/chroot && chmod 0755 /usr/sbin/chroot'

	docker exec "${CONTAINER}" mkdir -p \
		/scripts/provision/system \
		/scripts/provision/user

	for name in 10-apt-base 15-user 20-docker-engine 40-cleanup-ubuntu 40-fish 60-wsl-conf; do
		# shellcheck disable=SC2016 # $(id -u) must expand inside the generated script, not here
		printf '#!/usr/bin/env bash\necho "system:%s:$(id -u)" >> /tmp/provision.log\n' "${name}" \
			> "${BATS_FILE_TMPDIR}/sys-${name}.sh"
		docker cp "${BATS_FILE_TMPDIR}/sys-${name}.sh" \
			"${CONTAINER}:/scripts/provision/system/${name}.sh"
		docker exec "${CONTAINER}" chmod 0755 "/scripts/provision/system/${name}.sh"
	done

	for name in 10-mise-install 20-bashrc 30-fish-config 40-mise-config; do
		# shellcheck disable=SC2016 # $(id -u) must expand inside the generated script, not here
		printf '#!/usr/bin/env bash\necho "user:%s:$(id -u)" >> /tmp/provision.log\n' "${name}" \
			> "${BATS_FILE_TMPDIR}/usr-${name}.sh"
		docker cp "${BATS_FILE_TMPDIR}/usr-${name}.sh" \
			"${CONTAINER}:/scripts/provision/user/${name}.sh"
		docker exec "${CONTAINER}" chmod 0755 "/scripts/provision/user/${name}.sh"
	done

	# create bind-mount targets and world-writable log for multi-uid writes
	docker exec "${CONTAINER}" mkdir -p \
		/mnt/test/dev/pts /mnt/test/proc /mnt/test/sys
	docker exec "${CONTAINER}" install -m 0666 /dev/null /tmp/provision.log

	docker cp "${SCRIPT_SH}" "${CONTAINER}:/provision-chroot.sh"
	docker exec "${CONTAINER}" chmod +x /provision-chroot.sh
	docker exec "${CONTAINER}" bash /provision-chroot.sh /mnt/test /scripts
}

teardown_file() {
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id" 2>/dev/null) || return 0
	docker rm --force "${CONTAINER}" > /dev/null 2>&1 || true
}

@test "system_phase_runs_as_uid0_when_chroot_executed" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" \
		grep --extended-regexp '^system:[^:]+:0$' /tmp/provision.log
	assert_success
}

@test "user_phase_runs_as_uid1100_when_chroot_executed" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" \
		grep --extended-regexp '^user:[^:]+:1100$' /tmp/provision.log
	assert_success
}

@test "system_phase_completes_before_user_phase_when_chroot_ordered" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" bash -c '
		last_sys=$(grep --line-number "^system:" /tmp/provision.log | tail -1 | cut -d: -f1)
		first_usr=$(grep --line-number "^user:" /tmp/provision.log | head -1 | cut -d: -f1)
		[ -n "${last_sys}" ] && [ -n "${first_usr}" ] && [ "${last_sys}" -lt "${first_usr}" ]
	'
	assert_success
}

@test "cleanup_ubuntu_included_in_system_loop_when_chroot_runs" {
	docker info &>/dev/null || skip "docker not available"
	CONTAINER=$(cat "${BATS_FILE_TMPDIR}/container_id")
	run docker exec "${CONTAINER}" \
		grep --fixed-strings 'system:40-cleanup-ubuntu:' /tmp/provision.log
	assert_success
}
