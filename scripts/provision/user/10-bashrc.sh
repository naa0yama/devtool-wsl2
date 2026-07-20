#!/usr/bin/env bash
set -euxo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

DRY_RUN="${DRY_RUN:-}"

_run() {
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] $*"
	else
		"$@"
	fi
}

# root 実行禁止 (HOME 依存)
if [[ "${EUID}" -eq 0 ]]; then
	log_erro "This script must not run as root (HOME-dependent)"
	exit 1
fi

# --- mkdir ~/.local/bin ~/.bashrc.d/devtool ---
log_info "Create ~/.local/bin and ~/.bashrc.d/devtool"
_run mkdir -p "${HOME}/.local/bin" "${HOME}/.bashrc.d/devtool"

# --- append bashrc block (idempotent) ---
MARKER="# devtool: bashrc"
if grep -qF "${MARKER}" "${HOME}/.bashrc" 2>/dev/null; then
	log_info "bashrc block already present, skipping"
else
	log_info "Appending .bashrc.d loader and fish exec to ~/.bashrc"
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] append bashrc block"
	else
		cat >> "${HOME}/.bashrc" <<- '_DOC_'

			# devtool: bashrc
			# Include ~/.bashrc.d/ when using login shell
			if [ -d ~/.bashrc.d ]; then
				for script in ~/.bashrc.d/*.sh; do
					[ -r "$script" ] && . "$script"
				done

				for script in ~/.bashrc.d/devtool/*.sh; do
					[ -r "$script" ] && . "$script"
				done
				unset script
			fi

			# Switch to fish for interactive
			# Note: REMOTE_CONTAINERS_IPC is set during Dev Containers userEnvProbe (undocumented)
			if [[ ! -v REMOTE_CONTAINERS_IPC ]] && [[ -z "$NO_FISH" ]] && command -v fish &> /dev/null; then
				exec fish --login
			fi
			_DOC_
	fi
fi

log_info "10-bashrc.sh done"
