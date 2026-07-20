#!/usr/bin/env bats
# Static checks for .github/workflows/qcow2.yml — grep-based workflow inspection

load '../helpers/common'

WORKFLOW="${BATS_TEST_DIRNAME}/../../.github/workflows/qcow2.yml"

@test "qcow2_workflow_calls_provision_chroot_when_provisioning" {
	run grep --fixed-strings 'provision-chroot.sh' "${WORKFLOW}"
	assert_success
}

@test "qcow2_workflow_removes_resolv_conf_after_chroot_when_provisioning" {
	# shellcheck disable=SC2016 # single quotes intentional — searching for literal ${MNT} in yaml
	run grep --fixed-strings 'rm -f "${MNT}/etc/resolv.conf"' "${WORKFLOW}"
	assert_success
}

@test "qcow2_workflow_verifies_user_1100_in_step_summary" {
	run grep --fixed-strings "grep '^user:'" "${WORKFLOW}"
	assert_success
}

@test "qcow2_workflow_asserts_ubuntu_user_absent_in_step_summary" {
	run grep --fixed-strings "grep -q '^ubuntu:'" "${WORKFLOW}"
	assert_success
}

@test "qcow2_workflow_verifies_mise_binary_in_step_summary" {
	run grep --fixed-strings '.local/bin/mise' "${WORKFLOW}"
	assert_success
}
