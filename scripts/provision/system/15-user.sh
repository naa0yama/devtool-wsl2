#!/usr/bin/env bash
set -euo pipefail
[[ -n "${DEVTOOL_TRACE:-}" ]] && set -x

log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }

DEFAULT_UID="${DEFAULT_UID:-1100}"
DEFAULT_GID="${DEFAULT_GID:-1100}"
DEFAULT_USERNAME="${DEFAULT_USERNAME:-user}"
# WHY-NOT: /bin/bash 固定 — bare Ubuntu 経路では fish 未インストール → 実行不可。
#   baked WSL2/qcow2 は 40-fish.sh で fish を事前インストール済みのため、
#   DEVTOOL_USER_SHELL 未設定時のデフォルトを /usr/bin/fish とする。
#   ADR-0006 の「bare Ubuntu では bash」要件は呼び出し元 bootstrap.sh が
#   DEVTOOL_USER_SHELL=/bin/bash を渡すことで対処 (Cycle 8)。
DEVTOOL_USER_SHELL="${DEVTOOL_USER_SHELL:-/usr/bin/fish}"
# WHY-NOT: PROVISION_CHROOT を残す — test seam-α が sudoers.d 先を tmpdir に切替えるため必要。
#   空文字列時は本番パス (/etc/sudoers.d) に展開。
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
