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
#   - GPG: SSH RemoteForward creates socket directly (no systemd relay needed)
#   - SSH: Uses SSH ForwardAgent (no custom setup needed)
#   - Installs gpg-socket-cleanup.service to remove stale socket on login
#
# Usage:
#   WSL2:   ./setup.sh
#   Remote: ./setup.sh
#           curl -fsSL https://raw.githubusercontent.com/.../setup.sh | bash
#
# Lock file: ~/.cache/devtool-setup.lock
# =============================================================================

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

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
	fi
	# Remote: no special dependencies (SSH RemoteForward creates socket directly)

	if [ ${#missing[@]} -gt 0 ]; then
		log_erro "Missing dependencies: ${missing[*]}"
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

	tempdir=$(mktemp -d)
	cd "${tempdir}"

	curl "${CURL_OPTS[@]}" -O "${base_url}/npiperelay_checksums.txt"
	expected_hash=$(grep -E '\snpiperelay_windows_amd64.exe$' npiperelay_checksums.txt | cut -d' ' -f1)

	if [ -f "${NPIPERELAY}" ]; then
		current_hash=$(sha256sum "${NPIPERELAY}" | cut -d' ' -f1)

		if [ "${expected_hash}" = "${current_hash}" ]; then
			log_info "npiperelay ${NPIPERELAY_VERSION}: up to date"
			rm -rf "${tempdir}"
			return
		else
			log_warn "npiperelay: updating to ${NPIPERELAY_VERSION}"
		fi
	fi

	curl "${CURL_OPTS[@]}" -O "${base_url}/npiperelay_windows_amd64.exe"
	grep -E '\snpiperelay_windows_amd64.exe$' npiperelay_checksums.txt | sha256sum --status -c -

	mkdir -p "$(dirname "${NPIPERELAY}")"
	cp -v npiperelay_windows_amd64.exe "${NPIPERELAY}"
	chmod +x "${NPIPERELAY}"
	rm -rf "${tempdir}"
	log_info "npiperelay ${NPIPERELAY_VERSION}: installed: ${NPIPERELAY}"
}

install_gpg_bridge() {
	local tempdir base_url zip_name new_hash current_hash
	base_url="https://github.com/BusyJay/gpg-bridge/releases/download/${GPG_BRIDGE_VERSION}"
	zip_name="gpg-bridge-${GPG_BRIDGE_VERSION}.zip"

	tempdir=$(mktemp -d)
	cd "${tempdir}"

	curl "${CURL_OPTS[@]}" -O "${base_url}/${zip_name}"
	unzip -q "${zip_name}"

	new_hash=$(sha256sum gpg-bridge.exe | cut -d' ' -f1)

	if [ -f "${GPG_BRIDGE}" ]; then
		current_hash=$(sha256sum "${GPG_BRIDGE}" | cut -d' ' -f1)

		if [ "${new_hash}" = "${current_hash}" ]; then
			log_info "gpg-bridge ${GPG_BRIDGE_VERSION}: up to date"
			rm -rf "${tempdir}"
			return
		else
			log_warn "gpg-bridge: updating to ${GPG_BRIDGE_VERSION}"
		fi
	fi

	mkdir -p "$(dirname "${GPG_BRIDGE}")"
	cp -v gpg-bridge.exe "${GPG_BRIDGE}"
	chmod +x "${GPG_BRIDGE}"
	rm -rf "${tempdir}"
	log_info "gpg-bridge ${GPG_BRIDGE_VERSION}: installed: ${GPG_BRIDGE}"
}

install_yubikey_tool() {
	if [ ! -f "${YUBIKEY_TOOL_SRC}" ]; then
		log_warn "yubikey-tool: source not found, skipping"
		return
	fi

	local src_hash="" dst_hash="" needs_update=false

	src_hash=$(sha256sum "${YUBIKEY_TOOL_SRC}" | cut -d' ' -f1)

	if [ -f "${YUBIKEY_TOOL}" ]; then
		dst_hash=$(sha256sum "${YUBIKEY_TOOL}" | cut -d' ' -f1)

		if [ "${src_hash}" = "${dst_hash}" ]; then
			log_info "yubikey-tool: up to date"
			return
		else
			needs_update=true
			log_warn "yubikey-tool: updating"
		fi
	fi

	mkdir -p "$(dirname "${YUBIKEY_TOOL}")"
	cp -v "${YUBIKEY_TOOL_SRC}" "${YUBIKEY_TOOL}"
	log_info "yubikey-tool: installed: ${YUBIKEY_TOOL}"

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

	log_info "Configuring GPG..."

	mkdir -p "$(dirname "${gpg_conf}")"
	chmod 700 "$(dirname "${gpg_conf}")"

	if [ -f "${gpg_conf}" ]; then
		if ! grep -q '^no-autostart' "${gpg_conf}"; then
			echo "no-autostart" >> "${gpg_conf}"
			log_info "gpg.conf: added 'no-autostart'"
		else
			log_info "gpg.conf: 'no-autostart' already set"
		fi
	else
		echo "no-autostart" > "${gpg_conf}"
		log_info "${gpg_conf}: created with 'no-autostart'"
	fi

	# Mask local gpg-agent services to prevent conflicts
	systemctl --user mask gpg-agent.service gpg-agent.socket \
		gpg-agent-ssh.socket gpg-agent-extra.socket gpg-agent-browser.socket \
		2>/dev/null || true
	log_info "gpg-agent systemd units: masked"
}

install_systemd_units_wsl2() {
	local systemd_dst="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

	log_info "Installing systemd user units (WSL2)..."
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
ListenStream=%t/gnupg/S.gpg-agent.extra
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

	log_info "systemd units: installed"
}

install_systemd_units_remote() {
	local systemd_dst="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

	log_info "Installing systemd user units (Remote)..."
	mkdir -p "${systemd_dst}"

	# Remove old gpg-agent.socket and gpg-agent@.service if they exist
	if [ -f "${systemd_dst}/gpg-agent.socket" ]; then
		systemctl --user disable --now gpg-agent.socket 2>/dev/null || true
		rm -f "${systemd_dst}/gpg-agent.socket"
		log_info "gpg-agent.socket: removed (old)"
	fi
	rm -f "${systemd_dst}/gpg-agent@.service"

	# gpg-socket-cleanup.service
	# Removes stale GPG socket on login so SSH RemoteForward can create it
	# Also creates extra socket symlink for devcontainer GPG forwarding
	cat > "${systemd_dst}/gpg-socket-cleanup.service" << 'EOF'
[Unit]
Description=Clean up GPG agent socket for SSH RemoteForward
Documentation=man:gpg-agent(1)
# Run early in the login process, before SSH connection is fully established
DefaultDependencies=no
Before=default.target

[Service]
Type=oneshot
ExecStart=/bin/rm -f %t/gnupg/S.gpg-agent %t/gnupg/S.gpg-agent.extra
ExecStart=/bin/mkdir -p %t/gnupg
ExecStart=/bin/ln -sf S.gpg-agent %t/gnupg/S.gpg-agent.extra
RemainAfterExit=no

[Install]
WantedBy=default.target
EOF

	systemctl --user daemon-reload
	systemctl --user enable gpg-socket-cleanup.service

	log_info "systemd units: installed"
}

install_shell_config_wsl2() {
	local bashrc_d="${HOME}/.bashrc.d"

	log_info "Installing shell configuration..."
	mkdir -p "${bashrc_d}"

	# SSH agent config (WSL2: uses systemd socket)
	cat > "${bashrc_d}/21-ssh-agent.sh" << 'EOF'
#!/usr/bin/env bash

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m \$*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m \$*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m \$*" >&2; }

# SSH agent
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh/agent.sock"
if ! systemctl --user is-active --quiet ssh-agent.socket; then
    log_warn "ssh-agent.socket is not running"
    log_info "       Check with: journalctl --user -u ssh-agent.socket"
    log_info "       Start with: systemctl --user start ssh-agent.socket"
fi
EOF
	log_info "Created: ${bashrc_d}/21-ssh-agent.sh"

	# GPG agent config
	cat > "${bashrc_d}/22-gpg-agent.sh" << 'EOF'
#!/usr/bin/env bash

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m \$*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m \$*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m \$*" >&2; }

# GPG agent
if ! systemctl --user is-active --quiet gpg-agent.socket; then
    log_warn "gpg-agent.socket is not running"
    log_info "       Check with: journalctl --user -u gpg-agent.socket"
    log_info "       Start with: systemctl --user start gpg-agent.socket"
fi
EOF
	log_info "Created: ${bashrc_d}/22-gpg-agent.sh"
}

install_shell_config_remote() {
	local bashrc_d="${HOME}/.bashrc.d"

	log_info "Installing shell configuration..."
	mkdir -p "${bashrc_d}"

	# SSH: ForwardAgent sets SSH_AUTH_SOCK automatically, no config needed

	# GPG agent config - check if socket exists (created by SSH RemoteForward)
	cat > "${bashrc_d}/22-gpg-agent.sh" << 'EOF'
#!/usr/bin/env bash

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m \$*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m \$*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m \$*" >&2; }

# GPG agent socket (created by SSH RemoteForward)
__GPG_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gnupg/S.gpg-agent"
if [ ! -S "${__GPG_SOCK}" ]; then
    log_warn "GPG agent socket not found: ${__GPG_SOCK}"
    log_info "       Ensure SSH RemoteForward is configured on your Windows host"
fi
unset __GPG_SOCK
EOF
	log_info "Created: ${bashrc_d}/22-gpg-agent.sh"
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

	log_info "Windows install directory: ${WIN_INSTALL_DIR}"
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
	log_info "To re-run setup: rm ${LOCK_FILE}"
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
