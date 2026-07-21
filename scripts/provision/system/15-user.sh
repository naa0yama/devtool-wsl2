#!/usr/bin/env bash
set -euo pipefail
[[ -n "${DEVTOOL_TRACE:-}" ]] && set -x

log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }

DEFAULT_UID="${DEFAULT_UID:-1100}"
DEFAULT_GID="${DEFAULT_GID:-1100}"
DEFAULT_USERNAME="${DEFAULT_USERNAME:-user}"
# WHY-NOT: hardcoding /bin/bash — the bare Ubuntu path has no fish installed,
#   so it would fail. Baked WSL2/qcow2 already install fish via 40-fish.sh,
#   so /usr/bin/fish is the default when DEVTOOL_USER_SHELL is unset.
#   The ADR-0006 requirement "bare Ubuntu uses bash" is handled by the
#   caller bootstrap.sh passing DEVTOOL_USER_SHELL=/bin/bash (Cycle 8).
DEVTOOL_USER_SHELL="${DEVTOOL_USER_SHELL:-/usr/bin/fish}"
# WHY-NOT: dropping PROVISION_CHROOT — test seam-α needs it to redirect the
#   sudoers.d destination to a tmpdir. Empty string expands to the production
#   path (/etc/sudoers.d).
PROVISION_CHROOT="${PROVISION_CHROOT:-}"

# --- groupadd ---
log_info "Create group ${DEFAULT_USERNAME} (gid=${DEFAULT_GID})"
if getent group "${DEFAULT_USERNAME}" > /dev/null 2>&1; then
	log_info "group ${DEFAULT_USERNAME} already exists, skipping groupadd"
else
	groupadd --gid "${DEFAULT_GID}" "${DEFAULT_USERNAME}"
fi

# --- useradd ---
log_info "Create user ${DEFAULT_USERNAME} (uid=${DEFAULT_UID})"
if getent passwd "${DEFAULT_USERNAME}" > /dev/null 2>&1; then
	log_info "user ${DEFAULT_USERNAME} already exists, skipping useradd"
else
	useradd \
		--shell "${DEVTOOL_USER_SHELL}" \
		--uid "${DEFAULT_UID}" \
		--gid "${DEFAULT_GID}" \
		--create-home \
		"${DEFAULT_USERNAME}"
fi

# --- password ---
log_info "Lock password for ${DEFAULT_USERNAME} (NOPASSWD sudo is used instead)"
usermod --password '*' "${DEFAULT_USERNAME}"

# --- sudoers ---
log_info "Configure sudoers for ${DEFAULT_USERNAME}"
mkdir -p "${PROVISION_CHROOT}/etc/sudoers.d"
printf '%s\tALL=(ALL) NOPASSWD:ALL\n' "${DEFAULT_USERNAME}" \
	> "${PROVISION_CHROOT}/etc/sudoers.d/${DEFAULT_USERNAME}"
chmod 0440 "${PROVISION_CHROOT}/etc/sudoers.d/${DEFAULT_USERNAME}"

log_info "15-user.sh complete"
