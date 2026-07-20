#!/usr/bin/env bats
# seam-α: PATH stubs for curl, sh, id, getent, sudo; fake HOME + DEVTOOL_PROVISION_DIR
# No network, no root, no docker required.

load '../helpers/common'

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/provision/bootstrap.sh"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR

	FAKE_BIN="${TMPDIR}/bin"
	mkdir -p "${FAKE_BIN}"

	# id stub: default — user is already in docker group (skips usermod)
	cat > "${FAKE_BIN}/id" << 'IDEOF'
#!/bin/sh
case "$1" in
	-un) echo "user" ;;
	-nG) echo "sudo docker" ;;
esac
IDEOF
	chmod +x "${FAKE_BIN}/id"

	export PATH="${FAKE_BIN}:${PATH}"

	FAKE_HOME="${TMPDIR}/home"
	mkdir -p "${FAKE_HOME}"
	export HOME="${FAKE_HOME}"

	FAKE_PROV="${TMPDIR}/provision"
	mkdir -p "${FAKE_PROV}/user"
	export DEVTOOL_PROVISION_DIR="${FAKE_PROV}"
	export DEVTOOL_PHASE2_UID=1100
	export DEVTOOL_BOOTSTRAP_SELF="${SCRIPT}"
}

teardown() {
	rm --recursive --force "${TMPDIR}"
}

@test "phase2_exits_1_when_uid_is_not_1100" {
	run env DEVTOOL_BOOTSTRAP_PHASE=2 DEVTOOL_PHASE2_UID=1000 bash "${SCRIPT}"
	assert_equal "${status}" 1
}

@test "phase2_runs_mise_installer_when_mise_binary_missing_and_uid_is_1100" {
	# mock 10-mise-install.sh: calls curl when mise binary absent
	cat > "${FAKE_PROV}/user/10-mise-install.sh" << 'EOF'
#!/usr/bin/env bash
if [[ -x "${HOME}/.local/bin/mise" ]]; then exit 0; fi
curl https://mise.run | sh
EOF
	chmod +x "${FAKE_PROV}/user/10-mise-install.sh"

	# curl stub: log URL args to file
	cat > "${FAKE_BIN}/curl" << CURLEOF
#!/bin/sh
echo "\$@" >> "${TMPDIR}/curl.log"
CURLEOF
	chmod +x "${FAKE_BIN}/curl"

	# sh stub: drain stdin from curl pipe
	cat > "${FAKE_BIN}/sh" << 'SHEOF'
#!/bin/sh
cat > /dev/null
SHEOF
	chmod +x "${FAKE_BIN}/sh"

	run env DEVTOOL_BOOTSTRAP_PHASE=2 bash "${SCRIPT}"
	assert_success
	run grep --fixed-strings 'https://mise.run' "${TMPDIR}/curl.log"
	assert_success
}

@test "phase2_skips_mise_install_when_mise_binary_exists" {
	mkdir -p "${FAKE_HOME}/.local/bin"
	printf '#!/bin/sh\n' > "${FAKE_HOME}/.local/bin/mise"
	chmod +x "${FAKE_HOME}/.local/bin/mise"

	# mock 10-mise-install.sh: skips when mise binary exists
	cat > "${FAKE_PROV}/user/10-mise-install.sh" << 'EOF'
#!/usr/bin/env bash
if [[ -x "${HOME}/.local/bin/mise" ]]; then exit 0; fi
curl https://mise.run | sh
EOF
	chmod +x "${FAKE_PROV}/user/10-mise-install.sh"

	# curl stub: log to file if invoked
	cat > "${FAKE_BIN}/curl" << CURLEOF
#!/bin/sh
echo "\$@" >> "${TMPDIR}/curl.log"
CURLEOF
	chmod +x "${FAKE_BIN}/curl"

	run env DEVTOOL_BOOTSTRAP_PHASE=2 bash "${SCRIPT}"
	assert_success
	[ ! -f "${TMPDIR}/curl.log" ]
}

@test "phase2_calls_all_user_provision_scripts_when_uid_is_1100" {
	cat > "${FAKE_PROV}/user/10-first.sh" << FIRSTEOF
#!/usr/bin/env bash
echo "called:10-first.sh" >> "${TMPDIR}/call.log"
FIRSTEOF
	chmod +x "${FAKE_PROV}/user/10-first.sh"

	cat > "${FAKE_PROV}/user/20-second.sh" << SECONDEOF
#!/usr/bin/env bash
echo "called:20-second.sh" >> "${TMPDIR}/call.log"
SECONDEOF
	chmod +x "${FAKE_PROV}/user/20-second.sh"

	run env DEVTOOL_BOOTSTRAP_PHASE=2 bash "${SCRIPT}"
	assert_success
	run grep --fixed-strings 'called:10-first.sh' "${TMPDIR}/call.log"
	assert_success
	run grep --fixed-strings 'called:20-second.sh' "${TMPDIR}/call.log"
	assert_success
}

@test "phase2_runs_usermod_and_logs_gid_when_not_in_docker_group" {
	# id stub: user not in docker group
	cat > "${FAKE_BIN}/id" << 'IDEOF'
#!/bin/sh
case "$1" in
	-un) echo "user" ;;
	-nG) echo "sudo" ;;
esac
IDEOF
	chmod +x "${FAKE_BIN}/id"

	# getent stub: return docker group with gid 998
	cat > "${FAKE_BIN}/getent" << 'GETENTEOF'
#!/bin/sh
echo "docker:x:998:user"
GETENTEOF
	chmod +x "${FAKE_BIN}/getent"

	# sudo stub: log invocation
	cat > "${FAKE_BIN}/sudo" << SUDOEOF
#!/bin/sh
echo "\$@" >> "${TMPDIR}/sudo.log"
SUDOEOF
	chmod +x "${FAKE_BIN}/sudo"

	run bash -c "DEVTOOL_BOOTSTRAP_PHASE=2 bash '${SCRIPT}' 2>'${TMPDIR}/bootstrap.log'"
	assert_success
	run grep --fixed-strings 'usermod' "${TMPDIR}/sudo.log"
	assert_success
	run grep --fixed-strings 'gid=998' "${TMPDIR}/bootstrap.log"
	assert_success
}
