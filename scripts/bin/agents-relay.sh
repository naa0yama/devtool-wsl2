#!/bin/bash
set -euo pipefail

# setting
# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
__USERPROFILE="$(wslpath -u "$(powershell.exe -c '$env:USERPROFILE' | tr -d '\r')")"
CURL_OPTS="-sfSL --retry 3 --retry-delay 2 --retry-connrefused"
GPG_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gnupg/S.gpg-agent"
GPG_BRIDGE_PORT=4321
NPIPERELAY="/${__USERPROFILE}/.local/bin/npiperelay.exe"
SSH_NAMED_PIPE="//./pipe/openssh-ssh-agent"
SSH_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh/agent.sock"

# Install npiperelay.exe
if [ ! -f "${NPIPERELAY}" ]; then
	echo "Downloading albertony/npiperelay ..."
	__TEMPDIR=$(mktemp -d)
	cd "${__TEMPDIR}"
	curl "${CURL_OPTS}" -O "$(curl "${CURL_OPTS}" -H 'User-Agent: builder/1.0' \
		https://api.github.com/repos/albertony/npiperelay/releases/releases/latest | \
		jq -r '.assets[] | select(.name | endswith("npiperelay_windows_amd64.exe")) | .browser_download_url')"

	curl "${CURL_OPTS}" -O "$(curl "${CURL_OPTS}" -H 'User-Agent: builder/1.0' \
		https://api.github.com/repos/albertony/npiperelay/releases/releases/latest | \
		jq -r '.assets[] | select(.name | endswith("npiperelay_checksums.txt")) | .browser_download_url')"
	grep -E '\snpiperelay_windows_amd64.exe$' npiperelay_checksums.txt | sha256sum --status -c -

	cp -av npiperelay_windows_amd64.exe "$HOME/.local/bin/npiperelay.exe"
	chmod +x "$HOME/.local/bin/npiperelay.exe"
	type -p npiperelay.exe
	rm -rf "${__TEMPDIR}"
	echo "Downloading albertony/npiperelay ... done"
fi

# create directory
mkdir -p "$(dirname "$GPG_SOCKET")"
mkdir -p "$(dirname "$SSH_SOCKET")"

# Cleanup function (called by trap)
# shellcheck disable=SC2317
cleanup() {
    pkill -P $$ 2>/dev/null || true
    rm -f "$GPG_SOCKET" "$SSH_SOCKET"
}
trap cleanup EXIT INT TERM

# Delete an existing socket
rm -f "$GPG_SOCKET" "$SSH_SOCKET"

# GPG relay (TCP)
socat UNIX-LISTEN:"$GPG_SOCKET",fork,mode=600,unlink-early \
      TCP4:127.0.0.1:$GPG_BRIDGE_PORT &
GPG_PID=$!

# SSH Relay (Named Pipe)
socat UNIX-LISTEN:"$SSH_SOCKET",fork,mode=600,unlink-early \
      EXEC:"$NPIPERELAY -ei -ep -s '$SSH_NAMED_PIPE'",nofork &
SSH_PID=$!

echo "GPG relay started (PID: $GPG_PID): $GPG_SOCKET -> TCP:$GPG_BRIDGE_PORT"
echo "SSH relay started (PID: $SSH_PID): $SSH_SOCKET -> $SSH_NAMED_PIPE"

# Monitor the processes (end all when any one ends)
wait -n
exit $?
