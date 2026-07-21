#!/usr/bin/env bash
set -euo pipefail

# Bind mount targets: host_src:guest_relative_dst (mount order)
BIND_TARGETS=(
	"/dev:dev"
	"/proc:proc"
	"/sys:sys"
	"/dev/pts:dev/pts"
)

cleanup_mounts() {
	local mnt="$1"
	# WHY-NOT: reverse loop over BIND_TARGETS — /dev/pts must precede /dev (nested);
	#   explicit list makes the required order unambiguous without array arithmetic
	for m in "${mnt}/dev/pts" "${mnt}/dev" "${mnt}/proc" "${mnt}/sys" \
	         "${mnt}/run/systemd/resolve/stub-resolv.conf"; do
		mountpoint -q "${m}" 2>/dev/null && umount "${m}" || true
	done
	rm -f "${mnt}/run/systemd/resolve/stub-resolv.conf" 2>/dev/null || true
	rmdir --ignore-fail-on-non-empty \
		"${mnt}/run/systemd/resolve" "${mnt}/run/systemd" 2>/dev/null || true
}

# Allow sourcing for unit tests without executing main body
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

FORCE_FAIL=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dry-run) DRY_RUN=1; shift ;;
		--force-fail=*) FORCE_FAIL="${1#--force-fail=}"; shift ;;
		--) shift; break ;;
		*) break ;;
	esac
done

MNT="${1:?mount root required}"
# shellcheck disable=SC2034
# WHY-NOT: remove param — cycle-4 chroot exec will use SCRIPTS_SRC
SCRIPTS_SRC="${2:?scripts source dir required}"

exec_provision_in_chroot() {
	local mnt="$1" scripts_src="$2"
	# WHY-NOT: cp scripts to /tmp inside chroot — /opt/devtool は bootstrap.sh の DEVTOOL_SRC_ROOT 既定値と整合、無駄な移動を避ける
	mkdir -p "${mnt}/opt/devtool"
	cp -a "${scripts_src}" "${mnt}/opt/devtool/scripts"
	chroot "${mnt}" env DEVTOOL_ENV=vm DEVTOOL_SRC_ROOT=/opt/devtool \
		DEVTOOL_TRACE=1 \
		bash /opt/devtool/scripts/provision/bootstrap.sh
	chroot "${mnt}" bash /opt/devtool/scripts/image/finalize.sh
}

trap 'cleanup_mounts "${MNT}"' ERR EXIT

# Purity guard: assert guest resolv.conf is the expected stock Ubuntu symlink before touching the guest fs
# WHY-NOT: readlink guard を bind mount 後に置く — mount 後は bind 経由で symlink target 判定が変わり検出精度が落ちる
# WHY-NOT: readlink -f (絶対 path 解決) — 相対 symlink 文字列そのものが stock Ubuntu との一致条件、絶対 path 化すると意図せず match する
_resolv_link=$(readlink "${MNT}/etc/resolv.conf" 2>/dev/null || true)
if [[ "${_resolv_link}" != "../run/systemd/resolve/stub-resolv.conf" ]]; then
	echo "purity violation: ${MNT}/etc/resolv.conf must be a symlink to ../run/systemd/resolve/stub-resolv.conf (got: '${_resolv_link}')" >&2
	exit 1
fi

# resolv.conf stub: bind host resolver stub into guest without modifying symlink
mkdir -p "${MNT}/run/systemd/resolve"
touch "${MNT}/run/systemd/resolve/stub-resolv.conf"
mount --bind /run/systemd/resolve/stub-resolv.conf \
	"${MNT}/run/systemd/resolve/stub-resolv.conf"

[[ "${FORCE_FAIL}" == "post-bind-resolv" ]] && { echo "forced failure: post-bind-resolv" >&2; exit 1; }

for entry in "${BIND_TARGETS[@]}"; do
	src="${entry%%:*}"
	dst="${MNT}/${entry##*:}"
	mount --bind "${src}" "${dst}"
done

[[ "${FORCE_FAIL}" == "post-bind-dev" ]] && { echo "forced failure: post-bind-dev" >&2; exit 1; }

if [[ "${DRY_RUN}" -eq 1 ]]; then
	exit 0
fi

exec_provision_in_chroot "${MNT}" "${SCRIPTS_SRC}"
