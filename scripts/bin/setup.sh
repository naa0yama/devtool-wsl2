#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# setup.sh
# Setup script for GPG/SSH agent relay (WSL2 and Remote SSH)
#
# WSL2 mode:
#   - Installs npiperelay.exe, gpg-bridge.exe, yubikey-tool.ps1 (Windows side)
#   - Relays via Windows named pipes/sockets using npiperelay
#
# Remote mode:
#   - No Windows tools installed (gpg-bridge runs on Windows, not remote)
#   - GPG: Relays via systemd-socket-proxyd to gpg-bridge (default: 127.0.0.1:4321)
#   - SSH: Uses SSH ForwardAgent (no custom setup needed)
#   - Optional: GPG_BRIDGE_HOST, GPG_BRIDGE_PORT
#
# Usage:
#   WSL2:   ./setup.sh
#   Remote: ./setup.sh
#           curl -fsSL https://raw.githubusercontent.com/.../setup.sh | bash
#
# Lock file: ~/.cache/devtool-setup.lock
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_FILE="${HOME}/.cache/devtool-setup.lock"

## renovate: datasource=github-releases packageName=albertony/npiperelay versioning=semver automerge=true
NPIPERELAY_VERSION=v1.9.2

## renovate: datasource=github-releases packageName=BusyJay/gpg-bridge versioning=semver automerge=true
GPG_BRIDGE_VERSION=v0.1.1

CURL_OPTS=(-fsSL --retry 3 --retry-delay 2 --retry-connrefused)

# -----------------------------------------------------------------------------
# Environment detection
# -----------------------------------------------------------------------------
is_wsl2() {
	grep -Eqi 'microsoft|wsl' /proc/version 2>/dev/null
}

# Convert Windows paths: remove CR, convert backslashes to forward slashes
fixpath() {
	tr -d '\r' | tr '\\' '/'
}

# -----------------------------------------------------------------------------
# Dependencies check
# -----------------------------------------------------------------------------
check_dependencies() {
	local missing=()

	if is_wsl2; then
		# WSL2: needs curl and unzip for downloading Windows tools
		if ! command -v curl &>/dev/null; then
			missing+=("curl")
		fi
		if ! command -v unzip &>/dev/null; then
			missing+=("unzip")
		fi
	else
		# Remote: needs systemd-socket-proxyd for TCP relay
		if [ ! -x /usr/lib/systemd/systemd-socket-proxyd ]; then
			missing+=("systemd-socket-proxyd")
		fi
	fi

	if [ ${#missing[@]} -gt 0 ]; then
		echo "Error: Missing dependencies: ${missing[*]}" >&2
		exit 1
	fi
}

# -----------------------------------------------------------------------------
# WSL2 specific setup
# -----------------------------------------------------------------------------
setup_wsl2_vars() {
	POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

	# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
	USERPROFILE="$(wslpath -u "$("${POWERSHELL}" -NoProfile -c '$env:USERPROFILE' | fixpath)")"

	WIN_INSTALL_DIR="${USERPROFILE}/.local/bin"
	NPIPERELAY="${WIN_INSTALL_DIR}/npiperelay.exe"
	GPG_BRIDGE="${WIN_INSTALL_DIR}/gpg-bridge.exe"
	YUBIKEY_TOOL="${WIN_INSTALL_DIR}/yubikey-tool.ps1"
	YUBIKEY_TOOL_SRC="${SCRIPT_DIR}/yubikey-tool.ps1"

	# GPG paths from gpgconf.exe (Windows paths for npiperelay -a flag)
	GPG_AGENT_EXTRA_SOCK="$(gpgconf.exe --list-dirs agent-extra-socket | fixpath)"
}

install_npiperelay() {
	local tempdir base_url expected_hash current_hash
	base_url="https://github.com/albertony/npiperelay/releases/download/${NPIPERELAY_VERSION}"

	echo "Checking npiperelay ${NPIPERELAY_VERSION} ..."

	tempdir=$(mktemp -d)
	cd "${tempdir}"

	curl "${CURL_OPTS[@]}" -O "${base_url}/npiperelay_checksums.txt"
	expected_hash=$(grep -E '\snpiperelay_windows_amd64.exe$' npiperelay_checksums.txt | cut -d' ' -f1)

	if [ -f "${NPIPERELAY}" ]; then
		current_hash=$(sha256sum "${NPIPERELAY}" | cut -d' ' -f1)

		if [ "${expected_hash}" = "${current_hash}" ]; then
			echo "[OK] npiperelay.exe is up to date: ${NPIPERELAY}"
			rm -rf "${tempdir}"
			return
		else
			echo "[INFO] npiperelay.exe update available (${NPIPERELAY_VERSION})"
		fi
	fi

	curl "${CURL_OPTS[@]}" -O "${base_url}/npiperelay_windows_amd64.exe"
	grep -E '\snpiperelay_windows_amd64.exe$' npiperelay_checksums.txt | sha256sum --status -c -

	mkdir -p "$(dirname "${NPIPERELAY}")"
	cp -v npiperelay_windows_amd64.exe "${NPIPERELAY}"
	chmod +x "${NPIPERELAY}"
	rm -rf "${tempdir}"
	echo "[OK] npiperelay ${NPIPERELAY_VERSION} installed: ${NPIPERELAY}"
}

install_gpg_bridge() {
	local tempdir base_url zip_name new_hash current_hash
	base_url="https://github.com/BusyJay/gpg-bridge/releases/download/${GPG_BRIDGE_VERSION}"
	zip_name="gpg-bridge-${GPG_BRIDGE_VERSION}.zip"

	echo "Checking gpg-bridge ${GPG_BRIDGE_VERSION} ..."

	tempdir=$(mktemp -d)
	cd "${tempdir}"

	curl "${CURL_OPTS[@]}" -O "${base_url}/${zip_name}"
	unzip -q "${zip_name}"

	new_hash=$(sha256sum gpg-bridge.exe | cut -d' ' -f1)

	if [ -f "${GPG_BRIDGE}" ]; then
		current_hash=$(sha256sum "${GPG_BRIDGE}" | cut -d' ' -f1)

		if [ "${new_hash}" = "${current_hash}" ]; then
			echo "[OK] gpg-bridge.exe is up to date: ${GPG_BRIDGE}"
			rm -rf "${tempdir}"
			return
		else
			echo "[INFO] gpg-bridge.exe update available (${GPG_BRIDGE_VERSION})"
		fi
	fi

	mkdir -p "$(dirname "${GPG_BRIDGE}")"
	cp -v gpg-bridge.exe "${GPG_BRIDGE}"
	chmod +x "${GPG_BRIDGE}"
	rm -rf "${tempdir}"
	echo "[OK] gpg-bridge ${GPG_BRIDGE_VERSION} installed: ${GPG_BRIDGE}"
}

install_yubikey_tool() {
	if [ ! -f "${YUBIKEY_TOOL_SRC}" ]; then
		echo "[INFO] yubikey-tool.ps1 source not found, skipping"
		return
	fi

	local src_hash="" dst_hash="" needs_update=false

	src_hash=$(sha256sum "${YUBIKEY_TOOL_SRC}" | cut -d' ' -f1)

	if [ -f "${YUBIKEY_TOOL}" ]; then
		dst_hash=$(sha256sum "${YUBIKEY_TOOL}" | cut -d' ' -f1)

		if [ "${src_hash}" = "${dst_hash}" ]; then
			echo "[OK] yubikey-tool.ps1 is up to date: ${YUBIKEY_TOOL}"
			return
		else
			needs_update=true
			echo "[INFO] yubikey-tool.ps1 has been updated"
		fi
	fi

	mkdir -p "$(dirname "${YUBIKEY_TOOL}")"
	cp -v "${YUBIKEY_TOOL_SRC}" "${YUBIKEY_TOOL}"
	echo "[OK] yubikey-tool.ps1 installed: ${YUBIKEY_TOOL}"

	if [ "${needs_update}" = true ]; then
		echo ""
		echo "=========================================="
		echo " yubikey-tool.ps1 has been updated!"
		echo "=========================================="
		echo ""
		echo "To apply the update, run in PowerShell:"
		echo "  pwsh -c \"& '${YUBIKEY_TOOL}' -RemoveStartup; & '${YUBIKEY_TOOL}' -AddStartup\""
		echo ""
	else
		echo ""
		echo "To register yubikey-tool to Windows startup, run in PowerShell:"
		echo "  pwsh -File \"${YUBIKEY_TOOL}\" -AddStartup"
		echo ""
	fi
}

# -----------------------------------------------------------------------------
# Common setup
# -----------------------------------------------------------------------------
configure_gpg() {
	local gpg_conf="${GNUPGHOME:-$HOME/.gnupg}/gpg.conf"

	echo "Configuring GPG..."

	mkdir -p "$(dirname "${gpg_conf}")"
	chmod 700 "$(dirname "${gpg_conf}")"

	if [ -f "${gpg_conf}" ]; then
		if ! grep -q '^no-autostart' "${gpg_conf}"; then
			echo "no-autostart" >> "${gpg_conf}"
			echo "[OK] Added 'no-autostart' to ${gpg_conf}"
		else
			echo "[OK] 'no-autostart' already set in ${gpg_conf}"
		fi
	else
		echo "no-autostart" > "${gpg_conf}"
		echo "[OK] Created ${gpg_conf} with 'no-autostart'"
	fi

	# Mask local gpg-agent services to prevent conflicts
	systemctl --user mask gpg-agent.service gpg-agent.socket \
		gpg-agent-ssh.socket gpg-agent-extra.socket gpg-agent-browser.socket \
		2>/dev/null || true
	echo "[OK] Masked local gpg-agent systemd units"
}

install_systemd_units_wsl2() {
	local systemd_dst="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

	echo "Installing systemd user units (WSL2)..."
	mkdir -p "${systemd_dst}"

	# ssh-agent.socket
	cat > "${systemd_dst}/ssh-agent.socket" << 'EOF'
[Unit]
Description=SSH Agent Socket (relay to Windows OpenSSH Agent)
Documentation=man:ssh-agent(1)

[Socket]
ListenStream=%t/ssh/agent.sock
SocketMode=0600
DirectoryMode=0700
Accept=true

[Install]
WantedBy=sockets.target
EOF

	# ssh-agent@.service
	cat > "${systemd_dst}/ssh-agent@.service" << EOF
[Unit]
Description=SSH Agent Relay to Windows OpenSSH Agent (connection %i)
Documentation=man:ssh-agent(1)
Requires=ssh-agent.socket

[Service]
Type=simple
ExecStart=${NPIPERELAY} -ei -s //./pipe/openssh-ssh-agent
StandardInput=socket
StandardOutput=socket
StandardError=journal
EOF

	# gpg-agent.socket
	rm -f "${systemd_dst}/gpg-agent.socket"
	cat > "${systemd_dst}/gpg-agent.socket" << 'EOF'
[Unit]
Description=GPG Agent Socket (relay to Windows gpg-agent)
Documentation=man:gpg-agent(1)

[Socket]
ListenStream=%t/gnupg/S.gpg-agent
SocketMode=0600
DirectoryMode=0700
Accept=true

[Install]
WantedBy=sockets.target
EOF

	# gpg-agent@.service
	cat > "${systemd_dst}/gpg-agent@.service" << EOF
[Unit]
Description=GPG Agent Relay to Windows gpg-agent (connection %i)
Documentation=man:gpg-agent(1)
Requires=gpg-agent.socket

[Service]
Type=simple
ExecStart=${NPIPERELAY} -ei -ep -a '${GPG_AGENT_EXTRA_SOCK}'
StandardInput=socket
StandardOutput=socket
StandardError=journal
EOF

	systemctl --user daemon-reload
	systemctl --user enable --now ssh-agent.socket gpg-agent.socket

	echo "[OK] Systemd units installed and enabled: ${systemd_dst}"
}

install_systemd_units_remote() {
	local systemd_dst="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

	# Default to localhost (SSH RemoteForward) with gpg-bridge standard port
	local gpg_host="${GPG_BRIDGE_HOST:-127.0.0.1}"
	local gpg_port="${GPG_BRIDGE_PORT:-4321}"

	echo "Installing systemd user units (Remote)..."
	echo "  GPG Bridge: ${gpg_host}:${gpg_port}"
	echo "  SSH Agent: uses SSH ForwardAgent (no systemd unit needed)"
	mkdir -p "${systemd_dst}"

	# gpg-agent.socket
	cat > "${systemd_dst}/gpg-agent.socket" << 'EOF'
[Unit]
Description=GPG Agent Socket (relay to gpg-bridge)
Documentation=man:gpg-agent(1)

[Socket]
ListenStream=%t/gnupg/S.gpg-agent
SocketMode=0600
DirectoryMode=0700
Accept=true

[Install]
WantedBy=sockets.target
EOF

	# gpg-agent@.service
	cat > "${systemd_dst}/gpg-agent@.service" << EOF
[Unit]
Description=GPG Agent Relay to gpg-bridge (connection %i)
Documentation=man:gpg-agent(1)
Requires=gpg-agent.socket

[Service]
Type=simple
ExecStart=/usr/lib/systemd/systemd-socket-proxyd ${gpg_host}:${gpg_port}
EOF

	systemctl --user daemon-reload
	systemctl --user enable --now gpg-agent.socket

	echo "[OK] Systemd units installed and enabled: ${systemd_dst}"
}

install_shell_config_wsl2() {
	local bashrc_d="${HOME}/.bashrc.d"

	echo "Installing shell configuration..."
	mkdir -p "${bashrc_d}"

	# SSH agent config (WSL2: uses systemd socket)
	cat > "${bashrc_d}/21-ssh-agent.sh" << 'EOF'
#!/usr/bin/env bash

# Colors
__CLR_WARN='\033[0;33m'   # Yellow
__CLR_RESET='\033[0m'

# SSH agent
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh/agent.sock"
if ! systemctl --user is-active --quiet ssh-agent.socket; then
    echo -e "${__CLR_WARN}[WARN]${__CLR_RESET} ssh-agent.socket is not running"
    echo "       Check with: journalctl --user -u ssh-agent.socket"
    echo "       Start with: systemctl --user start ssh-agent.socket"
fi
EOF
	echo "[OK] Created ${bashrc_d}/21-ssh-agent.sh"

	# GPG agent config
	cat > "${bashrc_d}/22-gpg-agent.sh" << 'EOF'
#!/usr/bin/env bash

# Colors
__CLR_WARN='\033[0;33m'   # Yellow
__CLR_RESET='\033[0m'

# GPG agent
if ! systemctl --user is-active --quiet gpg-agent.socket; then
    echo -e "${__CLR_WARN}[WARN]${__CLR_RESET} gpg-agent.socket is not running"
    echo "       Check with: journalctl --user -u gpg-agent.socket"
    echo "       Start with: systemctl --user start gpg-agent.socket"
fi
EOF
	echo "[OK] Created ${bashrc_d}/22-gpg-agent.sh"
}

install_shell_config_remote() {
	local bashrc_d="${HOME}/.bashrc.d"

	echo "Installing shell configuration..."
	mkdir -p "${bashrc_d}"

	# SSH: ForwardAgent sets SSH_AUTH_SOCK automatically, no config needed

	# GPG agent config
	cat > "${bashrc_d}/22-gpg-agent.sh" << 'EOF'
#!/usr/bin/env bash

# Colors
__CLR_WARN='\033[0;33m'   # Yellow
__CLR_RESET='\033[0m'

# GPG agent
if ! systemctl --user is-active --quiet gpg-agent.socket; then
    echo -e "${__CLR_WARN}[WARN]${__CLR_RESET} gpg-agent.socket is not running"
    echo "       Check with: journalctl --user -u gpg-agent.socket"
    echo "       Start with: systemctl --user start gpg-agent.socket"
fi
EOF
	echo "[OK] Created ${bashrc_d}/22-gpg-agent.sh"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main_wsl2() {
	echo "============================================"
	echo " GPG/SSH Agent Tools Setup (WSL2)"
	echo "============================================"
	echo ""

	check_dependencies
	setup_wsl2_vars

	echo "Windows install directory: ${WIN_INSTALL_DIR}"
	echo ""

	install_npiperelay
	install_gpg_bridge
	install_yubikey_tool
	configure_gpg
	install_systemd_units_wsl2
	install_shell_config_wsl2

	# Create lock file
	mkdir -p "$(dirname "${LOCK_FILE}")"
	date -Iseconds > "${LOCK_FILE}"

	echo ""
	echo "============================================"
	echo " Setup complete!"
	echo "============================================"
	echo ""
	echo "To re-run setup: rm ${LOCK_FILE}"
}

main_remote() {
	echo "============================================"
	echo " GPG/SSH Agent Tools Setup (Remote)"
	echo "============================================"
	echo ""

	check_dependencies
	configure_gpg
	install_systemd_units_remote
	install_shell_config_remote

	# Create lock file
	mkdir -p "$(dirname "${LOCK_FILE}")"
	date -Iseconds > "${LOCK_FILE}"

	echo ""
	echo "============================================"
	echo " Setup complete!"
	echo "============================================"
	echo ""
	echo "To re-run setup: rm ${LOCK_FILE}"
}

main() {
	if is_wsl2; then
		main_wsl2
	else
		main_remote
	fi
}

main "$@"
