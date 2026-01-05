#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# agents-relay.sh
# GPG/SSH agent relay for WSL2 and Linux
#
# - GPG relay: Enabled when RemoteForward (TCP:4321) is available
# - SSH relay: Enabled when Windows Named Pipe exists (WSL2 only)
# =============================================================================

# -----------------------------------------------------------------------------
# Dependencies check
# -----------------------------------------------------------------------------
if ! command -v socat &>/dev/null; then
	echo "Error: socat is not installed" >&2
	exit 1
fi

# -----------------------------------------------------------------------------
# Environment detection
# -----------------------------------------------------------------------------
is_wsl2() {
	grep -Eqi 'microsoft|wsl' /proc/version 2>/dev/null
}

# Check if GPG RemoteForward is available (TCP port listening)
is_gpg_forward_available() {
	local port="${1:-4321}"
	# Test if we can connect to the forwarded port
	timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/${port}" 2>/dev/null
}

# Check if Windows SSH Named Pipe exists (WSL2 only)
is_ssh_pipe_available() {
	local pipe="$1"
	local npiperelay="$2"
	# Test if npiperelay can access the pipe
	[ -x "$npiperelay" ] && timeout 1 "$npiperelay" -q "$pipe" 2>/dev/null
}

# -----------------------------------------------------------------------------
# Settings
# -----------------------------------------------------------------------------
GPG_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gnupg/S.gpg-agent"
GPG_BRIDGE_PORT=4321
SSH_SOCKET="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh/agent.sock"
SSH_NAMED_PIPE="//./pipe/openssh-ssh-agent"

# WSL2 specific settings
if is_wsl2; then
	# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
	__USERPROFILE="$(wslpath -u "$(powershell.exe -c '$env:USERPROFILE' | tr -d '\r')")"
	NPIPERELAY="${__USERPROFILE}/.local/bin/npiperelay.exe"
	CURL_OPTS=(-sfSL --retry 3 --retry-delay 2 --retry-connrefused)
fi

# -----------------------------------------------------------------------------
# Install npiperelay.exe (WSL2 only)
# -----------------------------------------------------------------------------
install_npiperelay() {
	if [ ! -f "${NPIPERELAY}" ]; then
		echo "Downloading albertony/npiperelay ..."
		local tempdir
		tempdir=$(mktemp -d)
		cd "${tempdir}"

		curl "${CURL_OPTS[@]}" -O "$(curl "${CURL_OPTS[@]}" -H 'User-Agent: builder/1.0' \
			https://api.github.com/repos/albertony/npiperelay/releases/latest | \
			jq -r '.assets[] | select(.name | endswith("npiperelay_windows_amd64.exe")) | .browser_download_url')"

		curl "${CURL_OPTS[@]}" -O "$(curl "${CURL_OPTS[@]}" -H 'User-Agent: builder/1.0' \
			https://api.github.com/repos/albertony/npiperelay/releases/latest | \
			jq -r '.assets[] | select(.name | endswith("npiperelay_checksums.txt")) | .browser_download_url')"

		grep -E '\snpiperelay_windows_amd64.exe$' npiperelay_checksums.txt | sha256sum --status -c -

		mkdir -p "$(dirname "${NPIPERELAY}")"
		cp -av npiperelay_windows_amd64.exe "${NPIPERELAY}"
		chmod +x "${NPIPERELAY}"
		rm -rf "${tempdir}"
		echo "Downloading albertony/npiperelay ... done"
	fi
}

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
GPG_PID=""
SSH_PID=""

# shellcheck disable=SC2317
cleanup() {
	if [ -n "$GPG_PID" ]; then
		kill "$GPG_PID" 2>/dev/null || true
	fi
	if [ -n "$SSH_PID" ]; then
		kill "$SSH_PID" 2>/dev/null || true
	fi
	rm -f "$GPG_SOCKET" "$SSH_SOCKET"
}
trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
RELAY_STARTED=false

# --- GPG Relay (TCP RemoteForward) ---
if is_gpg_forward_available "$GPG_BRIDGE_PORT"; then
	mkdir -p "$(dirname "$GPG_SOCKET")"
	rm -f "$GPG_SOCKET"

	socat UNIX-LISTEN:"$GPG_SOCKET",fork,mode=600,unlink-early \
		TCP4:127.0.0.1:"$GPG_BRIDGE_PORT" &
	GPG_PID=$!
	echo "GPG relay started (PID: $GPG_PID): $GPG_SOCKET -> TCP:$GPG_BRIDGE_PORT"
	RELAY_STARTED=true
else
    echo "GPG relay skipped: RemoteForward port $GPG_BRIDGE_PORT not available"
fi

# --- SSH Relay (Windows Named Pipe, WSL2 only) ---
if is_wsl2; then
	install_npiperelay

	if is_ssh_pipe_available "$SSH_NAMED_PIPE" "$NPIPERELAY"; then
		mkdir -p "$(dirname "$SSH_SOCKET")"
		rm -f "$SSH_SOCKET"

		socat UNIX-LISTEN:"$SSH_SOCKET",fork,mode=600,unlink-early \
			EXEC:"'$NPIPERELAY' -ei -ep -s '$SSH_NAMED_PIPE'",nofork &
		SSH_PID=$!
		echo "SSH relay started (PID: $SSH_PID): $SSH_SOCKET -> $SSH_NAMED_PIPE"
		RELAY_STARTED=true
	else
		echo "SSH relay skipped: Named pipe $SSH_NAMED_PIPE not available"
	fi
else
	echo "SSH relay skipped: Not running on WSL2"
fi

# --- Wait for relays ---
if [ "$RELAY_STARTED" = true ]; then
	echo "Relay(s) running. Press Ctrl+C to stop."
	wait -n 2>/dev/null || wait
else
	echo "No relays started. Exiting."
	exit 1
fi
