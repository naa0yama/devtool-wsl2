#!/usr/bin/env bats
# Tests for documentation correctness after vestibule user pattern introduction (ADR-0006)

load '../helpers/common'

DOCS_ROOT="${BATS_TEST_DIRNAME}/../../docs"
PVE_IMPORT_MD="${DOCS_ROOT}/guides/pve-import.md"
BARE_UBUNTU_MD="${DOCS_ROOT}/guides/bare-ubuntu.md"
BOOTSTRAP_SPEC_MD="${DOCS_ROOT}/specs/components/bootstrap.md"

@test "pve_import_removes_no_create_home_reference" {
	run grep --fixed-strings "no-create-home" "${PVE_IMPORT_MD}"
	assert_failure
}

@test "pve_import_mentions_vestibule_pattern" {
	run grep --fixed-strings "vestibule" "${PVE_IMPORT_MD}"
	assert_success
}

@test "pve_import_uid_expected_is_1100_and_shell_bash" {
	run grep --fixed-strings "/bin/bash" "${PVE_IMPORT_MD}"
	assert_success
}

@test "bare_ubuntu_doc_exists" {
	run test -f "${BARE_UBUNTU_MD}"
	assert_success
}

@test "bare_ubuntu_curl_url_uses_releases_latest_download" {
	run grep --fixed-strings "releases/latest/download" "${BARE_UBUNTU_MD}"
	assert_success
}

@test "bootstrap_spec_doc_exists" {
	run test -f "${BOOTSTRAP_SPEC_MD}"
	assert_success
}

@test "bootstrap_spec_documents_stage0_phase1_phase2" {
	run grep --extended-regexp "stage 0|phase 1|phase 2" "${BOOTSTRAP_SPEC_MD}"
	assert_success
}
