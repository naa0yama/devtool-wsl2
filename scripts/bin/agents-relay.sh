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
	# Check npiperelay is executable and pipe exists via PowerShell
	[ -x "$npiperelay" ] && "${POWERSHELL}" -NoProfile -Command "Test-Path '${pipe}'" 2>/dev/null | grep -qi 'true'
}

# -----------------------------------------------------------------------------
# Settings
# -----------------------------------------------------------------------------
_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
_RUNTIME_DIR="${_RUNTIME_DIR%/}"
GPG_SOCKET="${_RUNTIME_DIR}/gnupg/S.gpg-agent"
GPG_BRIDGE_PORT=4321
SSH_SOCKET="${_RUNTIME_DIR}/ssh/agent.sock"
SSH_NAMED_PIPE="//./pipe/openssh-ssh-agent"

# WSL2 specific settings
if is_wsl2; then
	POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
	# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
	__USERPROFILE="$(wslpath -u "$("${POWERSHELL}" -NoProfile -c '$env:USERPROFILE' | tr -d '\r')")"
	NPIPERELAY="${__USERPROFILE}/.local/bin/npiperelay.exe"
	CURL_OPTS=(-sfSL --retry 3 --retry-delay 2 --retry-connrefused)
fi

# -----------------------------------------------------------------------------
# Install npiperelay.exe (WSL2 only)
# -----------------------------------------------------------------------------
install_npiperelay() {
	if [ ! -f "${NPIPERELAY}" ]; then
		echo "Downloading albertony/npiperelay ..."
		local tempdir release_json exe_url checksum_url
		local curl_user_agent='User-Agent: builder/1.0'

		# Check GitHub API rate limit first
		local rate_limit_json rate_limit rate_reset reset_time
		rate_limit_json=$(curl "${CURL_OPTS[@]}" -H "${curl_user_agent}" \
			https://api.github.com/rate_limit)
		rate_limit=$(echo "${rate_limit_json}" | jq -r '.rate.remaining')
		echo "GitHub API rate limit remaining: ${rate_limit}"
		if [ "${rate_limit}" -lt 2 ]; then
			rate_reset=$(echo "${rate_limit_json}" | jq -r '.rate.reset')
			reset_time=$(date -d "@${rate_reset}" +"%Y-%m-%dT%H:%M:%S%z")
			echo -e "\e[31mError: GitHub API rate limit exceeded. Reset at: ${reset_time}\e[0m" >&2
			exit 1
		fi

		# Fetch release info once and store in variable
		release_json=$(curl "${CURL_OPTS[@]}" -H "${curl_user_agent}" \
			https://api.github.com/repos/albertony/npiperelay/releases/latest)

		exe_url=$(echo "${release_json}" | \
			jq -r '.assets[] | select(.name | endswith("npiperelay_windows_amd64.exe")) | .browser_download_url')
		checksum_url=$(echo "${release_json}" | \
			jq -r '.assets[] | select(.name | endswith("npiperelay_checksums.txt")) | .browser_download_url')

		tempdir=$(mktemp -d)
		cd "${tempdir}"

		curl "${CURL_OPTS[@]}" -O "${exe_url}"
		curl "${CURL_OPTS[@]}" -O "${checksum_url}"

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
