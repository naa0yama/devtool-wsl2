#!/usr/bin/env bats
# Tests for scripts/image/finalize.sh (seam-3: scope isolation from bootstrap.sh)

load '../helpers/common'

FINALIZE_SH="${BATS_TEST_DIRNAME}/../../scripts/image/finalize.sh"
BOOTSTRAP_SH="${PROVISION_ROOT}/bootstrap.sh"

@test "finalize_sh_has_shebang_when_inspected" {
	run head --lines=1 "${FINALIZE_SH}"
	assert_success
	assert_output "#!/usr/bin/env bash"
}

@test "finalize_sh_is_executable_when_checked" {
	run test --file-exists-and-executable "${FINALIZE_SH}"
	# use bash -c to avoid bats portability issue with 'test -x'
	run bash -c "test -x '${FINALIZE_SH}'"
	assert_success
}

@test "finalize_sh_passes_shellcheck_when_linted" {
	run shellcheck --external-sources "${FINALIZE_SH}"
	assert_success
}

@test "bootstrap_sh_does_not_reference_finalize_sh_when_grepped" {
	run grep --fixed-strings "finalize" "${BOOTSTRAP_SH}"
	assert_failure
}

@test "finalize_sh_exits_zero_when_dry_run_is_set" {
	run env DRY_RUN=1 bash "${FINALIZE_SH}"
	assert_success
}
