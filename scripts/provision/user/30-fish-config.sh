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

write_if_changed() {
	local dest="$1"
	local content="$2"
	if [[ -f "${dest}" ]] && echo "${content}" | diff -q - "${dest}" > /dev/null 2>&1; then
		log_info "$(basename "${dest}") unchanged, skipping"
	else
		if [[ -n "${DRY_RUN}" ]]; then
			echo "[DRY_RUN] write ${dest}"
		else
			echo "${content}" > "${dest}"
			log_info "Written: ${dest}"
		fi
	fi
}

# root 実行禁止 (HOME 依存)
if [[ "${EUID}" -eq 0 ]]; then
	log_erro "This script must not run as root (HOME-dependent)"
	exit 1
fi

# --- ~/.config/mise ---
log_info "Create ~/.config/mise"
_run mkdir -p "${HOME}/.config/mise"

# --- fisher ---
log_info "Install fisher function"
_run mkdir -p "${HOME}/.config/fish/functions"
FISHER_DEST="${HOME}/.config/fish/functions/fisher.fish"
if [[ -f "${FISHER_DEST}" ]]; then
	log_info "fisher.fish already exists, skipping"
else
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] curl -sfSL -o ${FISHER_DEST} https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish"
	else
		curl -sfSL -o "${FISHER_DEST}" \
			https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish
	fi
fi

# --- ~/.config/fish/config.fish ---
log_info "Write ~/.config/fish/config.fish"
CONFIG_FISH_CONTENT='#!/usr/bin/env fish

# mise
/bin/mise activate fish | source
'
write_if_changed "${HOME}/.config/fish/config.fish" "${CONFIG_FISH_CONTENT}"

# --- ~/.config/fish/functions/fish_prompt.fish ---
log_info "Write ~/.config/fish/functions/fish_prompt.fish"
FISH_PROMPT_CONTENT='#!/usr/bin/env fish

function fish_prompt
	set_color green
	echo -n (prompt_pwd)
	set_color normal
	echo -n '"'"'> '"'"'
end
'
write_if_changed "${HOME}/.config/fish/functions/fish_prompt.fish" "${FISH_PROMPT_CONTENT}"

log_info "30-fish-config.sh done"
