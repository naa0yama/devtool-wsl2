#!/usr/bin/env bats
# seam-α: PATH stub for curl; env var seams; no network, no root required

load '../helpers/common'

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/provision/bootstrap.sh"
FIXTURE="${BATS_TEST_DIRNAME}/fixtures/devtool-provision.tar.gz"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR

	FAKE_BIN="${TMPDIR}/bin"
	mkdir -p "${FAKE_BIN}"

	# curl stub: -o target → write exit 42 script; no -o → cat fixture tarball to stdout
	cat > "${FAKE_BIN}/curl" <<EOF
#!/bin/sh
out=""
prev=""
for arg in "\$@"; do
	if [ "\${prev}" = "-o" ]; then
		out="\${arg}"
	fi
	prev="\${arg}"
done
if [ -n "\${out}" ]; then
	echo "\$@" >> "${TMPDIR}/curl-self.log"
	printf '#!/bin/sh\nexit 42\n' > "\${out}"
else
	echo "\$@" >> "${TMPDIR}/curl-provision.log"
	cat "${FIXTURE}"
fi
EOF
	chmod +x "${FAKE_BIN}/curl"

	export PATH="${FAKE_BIN}:${PATH}"

	FAKE_HOME="${TMPDIR}/home"
	mkdir -p "${FAKE_HOME}"
	export HOME="${FAKE_HOME}"

	umask 0077
}

teardown() {
	rm --recursive --force "${TMPDIR}"
}

_fake_prov_root() {
	local root="${TMPDIR}/provision-src"
	mkdir -p "${root}/scripts/provision/system" "${root}/scripts/provision/user"
	echo "${root}"
}

@test "curl_called_with_self_download_url_when_bash_source_ne_self" {
	export DEVTOOL_BOOTSTRAP_SELF="${TMPDIR}/bootstrap.sh"
	export UPSTREAM="https://example.com"
	export PROVISION_ASSET_URL="https://example.com/provision.tar.gz"
	export DEVTOOL_PROVISION_DIR="${TMPDIR}/provision"
	run bash "${SCRIPT}"
	assert_equal "${status}" 42
}

@test "stage0_self_download_skipped_when_self_file_exists" {
	local self_file="${TMPDIR}/bootstrap.sh"
	printf '#!/bin/sh\n' > "${self_file}"
	chmod +x "${self_file}"

	export DEVTOOL_BOOTSTRAP_SELF="${self_file}"
	export UPSTREAM="https://example.com"
	export PROVISION_ASSET_URL="https://example.com/provision.tar.gz"
	export DEVTOOL_PROVISION_DIR="${TMPDIR}/provision"
	export PROVISION_ROOT="$(_fake_prov_root)"
	export DRY_RUN=1
	export DEVTOOL_ENV=bare

	run bash "${SCRIPT}"
	assert_success
	[ ! -f "${TMPDIR}/curl-self.log" ]
}

@test "provision_tarball_extracted_to_provision_dir_when_stage0_runs" {
	local self_file="${TMPDIR}/bootstrap.sh"
	printf '#!/bin/sh\n' > "${self_file}"
	chmod +x "${self_file}"

	export DEVTOOL_BOOTSTRAP_SELF="${self_file}"
	export UPSTREAM="https://example.com"
	export PROVISION_ASSET_URL="https://example.com/provision.tar.gz"
	export DEVTOOL_PROVISION_DIR="${TMPDIR}/provision"
	export PROVISION_ROOT="$(_fake_prov_root)"
	export DRY_RUN=1
	export DEVTOOL_ENV=bare

	run bash "${SCRIPT}"
	assert_success
	[ -f "${TMPDIR}/provision/system/10-dummy.sh" ]
	[ -f "${TMPDIR}/provision/user/10-dummy.sh" ]
}

@test "provision_dir_has_other_read_bit_when_stage0_runs" {
	local self_file="${TMPDIR}/bootstrap.sh"
	printf '#!/bin/sh\n' > "${self_file}"
	chmod +x "${self_file}"

	export DEVTOOL_BOOTSTRAP_SELF="${self_file}"
	export UPSTREAM="https://example.com"
	export PROVISION_ASSET_URL="https://example.com/provision.tar.gz"
	export DEVTOOL_PROVISION_DIR="${TMPDIR}/provision"
	export PROVISION_ROOT="$(_fake_prov_root)"
	export DRY_RUN=1
	export DEVTOOL_ENV=bare

	run bash "${SCRIPT}"
	assert_success
	run bash -c "stat --format='%a' '${TMPDIR}/provision'"
	assert_output "755"
}

@test "provision_user_scripts_have_other_read_bit_when_stage0_runs" {
	local self_file="${TMPDIR}/bootstrap.sh"
	printf '#!/bin/sh\n' > "${self_file}"
	chmod +x "${self_file}"

	export DEVTOOL_BOOTSTRAP_SELF="${self_file}"
	export UPSTREAM="https://example.com"
	export PROVISION_ASSET_URL="https://example.com/provision.tar.gz"
	export DEVTOOL_PROVISION_DIR="${TMPDIR}/provision"
	export PROVISION_ROOT="$(_fake_prov_root)"
	export DRY_RUN=1
	export DEVTOOL_ENV=bare

	run bash "${SCRIPT}"
	assert_success
	run bash -c "stat --format='%a' '${TMPDIR}/provision/user/10-dummy.sh'"
	# chmod -R a+rX: 700 (extracted with umask 0077) → 755
	assert_output "755"
}
