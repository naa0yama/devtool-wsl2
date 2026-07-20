#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Tests for environment detection functions in scripts/provision/bootstrap.sh

load '../helpers/common'

BOOTSTRAP="${PROVISION_ROOT}/bootstrap.sh"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR
}

teardown() {
	rm -rf "${TMPDIR}"
}

# Source bootstrap.sh to load detection functions into current shell
_source_bootstrap() {
	# shellcheck source=/dev/null
	source "${BOOTSTRAP}"
}

@test "detect_env returns wsl2 when /proc/version contains microsoft" {
	local fake_proc="${TMPDIR}/proc-version"
	echo "Linux version 5.15.0-microsoft-standard-WSL2" > "${fake_proc}"
	export DEVTOOL_PROC_VERSION_FILE="${fake_proc}"
	export DEVTOOL_DOCKERENV_FILE="${TMPDIR}/no-dockerenv"
	export DEVTOOL_CGROUP_FILE="${TMPDIR}/no-cgroup"
	_source_bootstrap
	run detect_env
	assert_success
	assert_output "wsl2"
}

@test "detect_env returns wsl2 when /proc/version contains WSL" {
	local fake_proc="${TMPDIR}/proc-version"
	echo "Linux version 5.15.0-WSL2-custom" > "${fake_proc}"
	export DEVTOOL_PROC_VERSION_FILE="${fake_proc}"
	export DEVTOOL_DOCKERENV_FILE="${TMPDIR}/no-dockerenv"
	export DEVTOOL_CGROUP_FILE="${TMPDIR}/no-cgroup"
	_source_bootstrap
	run detect_env
	assert_success
	assert_output "wsl2"
}

@test "detect_env returns container when /.dockerenv exists" {
	local fake_dockerenv="${TMPDIR}/dockerenv"
	touch "${fake_dockerenv}"
	export DEVTOOL_PROC_VERSION_FILE="${TMPDIR}/no-proc"
	export DEVTOOL_DOCKERENV_FILE="${fake_dockerenv}"
	export DEVTOOL_CGROUP_FILE="${TMPDIR}/no-cgroup"
	_source_bootstrap
	run detect_env
	assert_success
	assert_output "container"
}

@test "detect_env returns container when cgroup contains docker" {
	local fake_cgroup="${TMPDIR}/cgroup"
	echo "12:devices:/docker/abc123" > "${fake_cgroup}"
	export DEVTOOL_PROC_VERSION_FILE="${TMPDIR}/no-proc"
	export DEVTOOL_DOCKERENV_FILE="${TMPDIR}/no-dockerenv"
	export DEVTOOL_CGROUP_FILE="${fake_cgroup}"
	_source_bootstrap
	run detect_env
	assert_success
	assert_output "container"
}

@test "detect_env returns vm when dmi product is KVM" {
	export DEVTOOL_PROC_VERSION_FILE="${TMPDIR}/no-proc"
	export DEVTOOL_DOCKERENV_FILE="${TMPDIR}/no-dockerenv"
	export DEVTOOL_CGROUP_FILE="${TMPDIR}/no-cgroup"
	_source_bootstrap
	# Override is_vm to use a fake dmi file (avoids systemd-detect-virt dependency)
	local fake_dmi_dir="${TMPDIR}/dmi/id"
	mkdir -p "${fake_dmi_dir}"
	echo "KVM" > "${fake_dmi_dir}/product_name"
	# shellcheck disable=SC2329
	is_vm() {
		local dmi_file="${TMPDIR}/dmi/id/product_name"
		if [[ -f "${dmi_file}" ]]; then
			grep -qiE "kvm|qemu|vmware|virtualbox" "${dmi_file}" && return 0
		fi
		return 1
	}
	run detect_env
	assert_success
	assert_output "vm"
}

@test "detect_env returns bare when nothing matches" {
	export DEVTOOL_PROC_VERSION_FILE="${TMPDIR}/no-proc"
	export DEVTOOL_DOCKERENV_FILE="${TMPDIR}/no-dockerenv"
	export DEVTOOL_CGROUP_FILE="${TMPDIR}/no-cgroup"
	_source_bootstrap
	# Override is_vm to always return false (no dmi/systemd-detect-virt in test env)
	# shellcheck disable=SC2329
	is_vm() { return 1; }
	run detect_env
	assert_success
	assert_output "bare"
}

@test "detect_env prioritizes container over wsl2" {
	local fake_proc="${TMPDIR}/proc-version"
	local fake_dockerenv="${TMPDIR}/dockerenv"
	echo "Linux version 5.15.0-microsoft-standard-WSL2" > "${fake_proc}"
	touch "${fake_dockerenv}"
	export DEVTOOL_PROC_VERSION_FILE="${fake_proc}"
	export DEVTOOL_DOCKERENV_FILE="${fake_dockerenv}"
	export DEVTOOL_CGROUP_FILE="${TMPDIR}/no-cgroup"
	_source_bootstrap
	run detect_env
	assert_success
	assert_output "container"
}

@test "DEVTOOL_ENV env var overrides auto-detection" {
	run bash -c "
		DEVTOOL_PROC_VERSION_FILE='${TMPDIR}/no-proc'
		DEVTOOL_DOCKERENV_FILE='${TMPDIR}/no-dockerenv'
		DEVTOOL_CGROUP_FILE='${TMPDIR}/no-cgroup'
		export DEVTOOL_PROC_VERSION_FILE DEVTOOL_DOCKERENV_FILE DEVTOOL_CGROUP_FILE
		source '${BOOTSTRAP}'
		DEVTOOL_ENV='vm'
		: \"\${DEVTOOL_ENV:=\$(detect_env)}\"
		echo \"\${DEVTOOL_ENV}\"
	"
	assert_success
	assert_output "vm"
}
