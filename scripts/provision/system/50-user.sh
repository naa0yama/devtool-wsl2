#!/usr/bin/env bash
set -euxo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

DRY_RUN="${DRY_RUN:-}"

DEFAULT_UID="${DEFAULT_UID:-1100}"
DEFAULT_GID="${DEFAULT_GID:-1100}"
DEFAULT_USERNAME="${DEFAULT_USERNAME:-user}"

_run() {
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] $*"
	else
		"$@"
	fi
}

# --- userdel ubuntu ---
log_info "Remove default ubuntu user if present"
if id ubuntu > /dev/null 2>&1; then
	_run userdel --remove ubuntu
else
	log_info "ubuntu user not found, skipping"
fi

# --- groupadd ---
log_info "Create group ${DEFAULT_USERNAME} (gid=${DEFAULT_GID})"
if getent group "${DEFAULT_GID}" > /dev/null 2>&1; then
	log_info "gid ${DEFAULT_GID} already exists, skipping groupadd"
else
	_run groupadd --gid "${DEFAULT_GID}" "${DEFAULT_USERNAME}"
fi

# --- useradd ---
log_info "Create user ${DEFAULT_USERNAME} (uid=${DEFAULT_UID})"
if id "${DEFAULT_USERNAME}" > /dev/null 2>&1; then
	log_info "User ${DEFAULT_USERNAME} already exists, skipping useradd"
else
	_run useradd -s /bin/bash --uid "${DEFAULT_UID}" --gid "${DEFAULT_GID}" -m "${DEFAULT_USERNAME}"
fi

# --- password ---
log_info "Set passwordless login for ${DEFAULT_USERNAME}"
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] echo ${DEFAULT_USERNAME}:password | chpasswd"
	echo "[DRY_RUN] passwd -d ${DEFAULT_USERNAME}"
else
	echo "${DEFAULT_USERNAME}:password" | chpasswd
	passwd -d "${DEFAULT_USERNAME}"
fi

# --- sudoers ---
log_info "Configure sudoers for ${DEFAULT_USERNAME}"
if [[ -n "${DRY_RUN}" ]]; then
	printf '[DRY_RUN] echo -e "%s\tALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/%s\n' "${DEFAULT_USERNAME}" "${DEFAULT_USERNAME}"
else
	echo -e "${DEFAULT_USERNAME}\tALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${DEFAULT_USERNAME}"
fi

log_info "50-user.sh complete"
