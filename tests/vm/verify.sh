#!/usr/bin/env bash
# Completion-state contract for a bootstrap.sh-provisioned VM.
# Runs as root inside the guest; asserts observable end state only,
# never bootstrap internals, so bootstrap refactors do not break it.
set -uo pipefail

FAILURES=0

_check() {
	local label="${1}"
	shift
	if "$@" > /dev/null 2>&1; then
		echo "ok: ${label}"
	else
		echo "FAIL: ${label}"
		FAILURES=$((FAILURES + 1))
	fi
}

DEFAULT_USERNAME="${DEFAULT_USERNAME:-user}"

_check "user ${DEFAULT_USERNAME} exists" id "${DEFAULT_USERNAME}"
_check "user ${DEFAULT_USERNAME} uid is 1100" test "$(id --user "${DEFAULT_USERNAME}" 2> /dev/null)" = "1100"
_check "user ${DEFAULT_USERNAME} gid is 1100" test "$(id --group "${DEFAULT_USERNAME}" 2> /dev/null)" = "1100"
_check "user ${DEFAULT_USERNAME} login shell is fish" bash -c "getent passwd '${DEFAULT_USERNAME}' | cut --delimiter=: --fields=7 | grep --quiet '/fish\$'"
_check "user ${DEFAULT_USERNAME} is in docker group" bash -c "id --name --groups '${DEFAULT_USERNAME}' | grep --quiet --word-regexp docker"

_check "fish is installed" command -v fish
_check "docker is installed" command -v docker
# shellcheck disable=SC2016 # single quotes intentional: ${HOME} must expand in the runuser subshell, not here
_check "mise is installed for ${DEFAULT_USERNAME}" runuser -u "${DEFAULT_USERNAME}" -- bash -c 'command -v mise || test -x "${HOME}/.local/bin/mise"'

_check "docker service is active" systemctl is-active docker

_check "/etc/devtool-release exists" test -f /etc/devtool-release

# 40-cleanup-ubuntu.sh must have removed the stock cloud-image user
_check "ubuntu user is absent" bash -c '! id ubuntu'

if [[ "${FAILURES}" -gt 0 ]]; then
	echo "verify.sh: ${FAILURES} check(s) failed"
	exit 1
fi
echo "verify.sh: all checks passed"
