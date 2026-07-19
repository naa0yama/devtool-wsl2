#!/usr/bin/env bash
set -euxo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

DRY_RUN="${DRY_RUN:-}"

DEVTOOL_ENV="${DEVTOOL_ENV:-wsl2}"
DEFAULT_USERNAME="${DEFAULT_USERNAME:-user}"
DEFAULT_UID="${DEFAULT_UID:-1100}"
DEFAULT_GID="${DEFAULT_GID:-1100}"
BUILD_REPOSITORY="${BUILD_REPOSITORY:-unknown}"
BUILD_BASE_REF="${BUILD_BASE_REF:-unknown}"
BUILD_ACTION="${BUILD_ACTION:-unknown}"
BUILD_SHA="${BUILD_SHA:-unknown}"

_run() {
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] $*"
	else
		"$@"
	fi
}

# Write file only when content differs (idempotent)
write_if_changed() {
	local dest="$1"
	local content="$2"

	if [[ -f "${dest}" ]]; then
		local existing_hash new_hash
		existing_hash="$(echo "${content}" | sha256sum | cut -d' ' -f1)"
		new_hash="$(sha256sum "${dest}" | cut -d' ' -f1)"
		if [[ "${existing_hash}" == "${new_hash}" ]]; then
			log_info "${dest} is up to date, skipping"
			return 0
		fi
	fi

	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] write ${dest}"
	else
		echo "${content}" > "${dest}"
		log_info "Wrote ${dest}"
	fi
}

# --- /etc/devtool-release (all targets) ---
log_info "Generate /etc/devtool-release"
devtool_release_content="BUILD_REPOSITORY=\"${BUILD_REPOSITORY}\"
BUILD_BASE_REF=\"${BUILD_BASE_REF}\"
BUILD_DATE=\"$(date +%Y-%m-%dT%H:%M:%S%z)\"
BUILD_ACTION=\"${BUILD_ACTION}\"
BUILD_SHA=\"${BUILD_SHA}\""

write_if_changed /etc/devtool-release "${devtool_release_content}"

# --- /etc/wsl.conf (wsl2 only) ---
if [[ "${DEVTOOL_ENV}" != "wsl2" ]]; then
	log_info "DEVTOOL_ENV=${DEVTOOL_ENV}, skipping /etc/wsl.conf"
else
	log_info "Generate /etc/wsl.conf"
	wsl_conf_content="[automount]
enabled=true
mountFsTab=true
root=\"/mnt/\"
options=\"metadata,uid=${DEFAULT_UID},gid=${DEFAULT_GID},umask=0022\"

[user]
default=${DEFAULT_USERNAME}

[boot]
systemd=true
"
	write_if_changed /etc/wsl.conf "${wsl_conf_content}"
fi

log_info "60-wsl-conf.sh complete"
