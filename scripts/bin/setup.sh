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
#   - Configures sshd: StreamLocalBindUnlink yes for current user (via sudo)
#   - Displays Windows SSH client config (RemoteForward for GPG, ForwardAgent for SSH)
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

# SCRIPT_DIR: empty when piped (curl | bash), set when executed directly
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" ]]; then
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
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
	# shellcheck disable=SC1003
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

configure_sshd_remote() {
	local sshd_conf="/etc/ssh/sshd_config.d/50-stream-local-bind-unlink.conf"
	local current_user
	current_user="$(id -un)"

	log_info "Configuring sshd for StreamLocalBindUnlink..."
	echo ""
	echo "This will create: ${sshd_conf}"
	echo "With the following content:"
	echo ""
	echo "  # Allow StreamLocalBindUnlink for user: ${current_user}"
	echo "  # This enables SSH RemoteForward to overwrite existing sockets"
	echo "  Match User ${current_user}"
	echo "      StreamLocalBindUnlink yes"
	echo ""

	if [ -f "${sshd_conf}" ]; then
		if grep -q "Match User ${current_user}" "${sshd_conf}" 2>/dev/null; then
			log_info "sshd config: already configured for user ${current_user}"
			return
		fi
	fi

	log_info "Running sudo to write sshd configuration..."
	sudo tee "${sshd_conf}" > /dev/null << EOF
# Allow StreamLocalBindUnlink for user: ${current_user}
# This enables SSH RemoteForward to overwrite existing sockets
Match User ${current_user}
    StreamLocalBindUnlink yes
EOF

	log_info "sshd config: created ${sshd_conf}"
	log_info "Restarting sshd..."
	# Debian/Ubuntu: ssh.service, RHEL/CentOS: sshd.service
	if systemctl list-unit-files ssh.service &>/dev/null; then
		sudo systemctl restart ssh
	else
		sudo systemctl restart sshd
	fi
	log_info "sshd: restarted"
}

show_remote_setup_instructions() {
	local uid gpg_sock_dir
	uid="$(id -u)"
	gpg_sock_dir="/run/user/${uid}/gnupg"

	echo ""
	log_info "=== Windows SSH Client Configuration ==="
	echo ""
	echo "Add to your Windows SSH config (~/.ssh/config):"
	echo ""
	echo "  Host your-remote-host"
	echo "      HostName example.com"
	echo "      User $(id -un)"
	echo "      ForwardAgent yes"
	echo "      RemoteForward ${gpg_sock_dir}/S.gpg-agent 127.0.0.1:4321"
	echo "      RemoteForward ${gpg_sock_dir}/S.gpg-agent.extra 127.0.0.1:4321"
	echo ""
}

install_ssh_rc_remote() {
	local ssh_rc="${HOME}/.ssh/rc"

	log_info "Installing ${ssh_rc} for SSH agent forwarding (tmux compatible)..."

	# Ensure ~/.ssh exists with secure permissions
	mkdir -p "${HOME}/.ssh"
	chmod 0700 "${HOME}/.ssh"

	if [ -f "${ssh_rc}" ]; then
		if grep -q 'SSH_AUTH_SOCK' "${ssh_rc}" 2>/dev/null; then
			log_info "${ssh_rc}: SSH_AUTH_SOCK handling already configured"
			return
		fi
		log_warn "${ssh_rc} exists, appending SSH agent configuration"
		echo "" >> "${ssh_rc}"
	fi

	# shellcheck disable=SC2016
	cat >> "${ssh_rc}" << 'EOF'
# shellcheck shell=sh
# SSH agent forwarding: create symlink to fixed path for tmux compatibility
# Note: sshd executes this as `/bin/sh ~/.ssh/rc`
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 0700 "$HOME/.ssh"
    ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/agent.sock"
fi
EOF

	chmod 0600 "${ssh_rc}"
	log_info "Created: ${ssh_rc}"
}

install_shell_config_remote() {
	local bashrc_d="${HOME}/.bashrc.d"
	local bashrc="${HOME}/.bashrc"

	log_info "Installing shell configuration (Remote)..."
	mkdir -p "${bashrc_d}"

	# SSH agent config (Remote: uses fixed symlink path)
	cat > "${bashrc_d}/21-ssh-agent.sh" << 'EOF'
#!/usr/bin/env bash
# SSH agent forwarding (fixed path for tmux compatibility)
# Symlink is created by ~/.ssh/rc on SSH login

_ssh_agent_sock="$HOME/.ssh/agent.sock"
if [ -S "$_ssh_agent_sock" ]; then
    export SSH_AUTH_SOCK="$_ssh_agent_sock"
fi
unset _ssh_agent_sock
EOF
	log_info "Created: ${bashrc_d}/21-ssh-agent.sh"

	# Check if .bashrc sources ~/.bashrc.d/*.sh
	if ! grep -q 'bashrc\.d' "${bashrc}" 2>/dev/null; then
		log_info "Adding ${bashrc_d} loader to ${bashrc}..."
		# shellcheck disable=SC2016
		cat >> "${bashrc}" << 'EOF'

# Include ~/.bashrc.d/*.sh
if [ -d "$HOME/.bashrc.d" ]; then
    for script in "$HOME/.bashrc.d"/*.sh; do
        # shellcheck source=/dev/null
        [ -r "$script" ] && . "$script"
    done
    unset script
fi
EOF
		log_info "Updated: ${bashrc}"
	else
		log_info "${bashrc}: already sources ${bashrc_d}"
	fi
}

install_shell_config_wsl2() {
	local bashrc_d="${HOME}/.bashrc.d"
	local environment_d="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"

	log_info "Installing shell configuration..."
	mkdir -p "${bashrc_d}"

	# SSH_AUTH_SOCK via environment.d (applies to all sessions including non-interactive)
	mkdir -p "${environment_d}"
	cat > "${environment_d}/21-ssh-agent.conf" << 'EOF'
SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/ssh/agent.sock
EOF
	log_info "Created: ${environment_d}/21-ssh-agent.conf"

	# Apply immediately if systemd user session is running
	# environment.d is only read at session start, so set-environment is needed for the current session
	if systemctl --user is-system-running &>/dev/null; then
		systemctl --user set-environment "SSH_AUTH_SOCK=${XDG_RUNTIME_DIR}/ssh/agent.sock"
		log_info "SSH_AUTH_SOCK: applied to current systemd user session"
	else
		log_warn "systemd user session not running, SSH_AUTH_SOCK will be set on next login"
	fi

	# SSH agent health check (WSL2: uses systemd socket)
	# Note: SSH_AUTH_SOCK is set via ~/.config/environment.d/21-ssh-agent.conf
	cat > "${bashrc_d}/21-ssh-agent.sh" << 'EOF'
#!/usr/bin/env bash
# SSH agent health check for interactive shells
# SSH_AUTH_SOCK is set via ~/.config/environment.d/21-ssh-agent.conf

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# Wait for systemd user session to be ready (max 5 seconds)
# This handles WSL startup race condition where bash starts before D-Bus is ready
__wait_systemd_user() {
    local i
    for i in 1 2 3 4 5; do
        if systemctl --user is-system-running &>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    log_warn "XDG_RUNTIME_DIR not set, systemd user session not available"
elif ! __wait_systemd_user; then
    log_warn "systemd user session not ready (timed out)"
elif ! systemctl --user is-active --quiet ssh-agent.socket; then
    log_warn "ssh-agent.socket is not running"
    log_info "       Check with: journalctl --user -u ssh-agent.socket"
    log_info "       Start with: systemctl --user start ssh-agent.socket"
fi

unset -f __wait_systemd_user
EOF
	log_info "Created: ${bashrc_d}/21-ssh-agent.sh"

	# GPG agent config
	cat > "${bashrc_d}/22-gpg-agent.sh" << 'EOF'
#!/usr/bin/env bash

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# GPG agent
# Note: 21-ssh-agent.sh already waits for systemd user session
if systemctl --user is-system-running &>/dev/null; then
    if ! systemctl --user is-active --quiet gpg-agent.socket; then
        log_warn "gpg-agent.socket is not running"
        log_info "       Check with: journalctl --user -u gpg-agent.socket"
        log_info "       Start with: systemctl --user start gpg-agent.socket"
    fi
fi
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
	configure_sshd_remote
	install_ssh_rc_remote
	install_shell_config_remote
	show_remote_setup_instructions

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

main() {
	if is_wsl2; then
		main_wsl2
	else
		main_remote
	fi
}

main "$@"
