#!/usr/bin/env bats
# seam-α: PATH stub for curl; fake HOME — no network, no root required

load '../helpers/common'

SCRIPT="${PROVISION_ROOT}/user/10-mise-install.sh"

setup() {
	TMPDIR="$(mktemp --directory)"
	export TMPDIR

	FAKE_BIN="${TMPDIR}/bin"
	mkdir -p "${FAKE_BIN}"

	# curl stub: record call to curl.log; exit 0
	cat > "${FAKE_BIN}/curl" <<'EOF'
#!/bin/sh
echo "$@" >> "${TMPDIR}/curl.log"
exit 0
EOF
	chmod +x "${FAKE_BIN}/curl"

	# sh stub: no-op (piped from curl stub)
	cat > "${FAKE_BIN}/sh" <<'STUBEOF'
#!/bin/sh
cat > /dev/null
exit 0
STUBEOF
	chmod +x "${FAKE_BIN}/sh"

	export PATH="${FAKE_BIN}:${PATH}"

	FAKE_HOME="${TMPDIR}/home"
	mkdir -p "${FAKE_HOME}"
	export HOME="${FAKE_HOME}"
}

teardown() {
	rm --recursive --force "${TMPDIR}"
}

@test "curl_called_with_mise_run_url_when_mise_not_installed" {
	run bash "${SCRIPT}"
	assert_success
	run grep --fixed-strings 'https://mise.run' "${TMPDIR}/curl.log"
	assert_success
}

@test "script_exits_zero_when_mise_already_exists_and_skips_curl" {
	mkdir -p "${FAKE_HOME}/.local/bin"
	# fake mise binary
	printf '#!/bin/sh\n' > "${FAKE_HOME}/.local/bin/mise"
	chmod +x "${FAKE_HOME}/.local/bin/mise"

	run bash "${SCRIPT}"
	assert_success
	[ ! -f "${TMPDIR}/curl.log" ]
}
