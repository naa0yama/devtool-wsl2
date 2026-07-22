#!/usr/bin/env bash
set -euo pipefail
[[ -n "${DEVTOOL_TRACE:-}" ]] && set -x

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

TZ="${TZ:-Asia/Tokyo}"
DRY_RUN="${DRY_RUN:-}"
DEVTOOL_ENV="${DEVTOOL_ENV:-wsl}"

_apt_get() {
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] apt-get $*"
	else
		apt-get "$@"
	fi
}

# WHY: mirror fetches (archive.ubuntu.com and friends) occasionally trickle
#   at near-zero throughput without ever hitting a hard stop, so apt's own
#   Acquire::http::Timeout (dead-connection detection only) never fires;
#   wrapping each attempt in `timeout` forces an abort even on a live-but-slow
#   transfer, and retrying starts a fresh connection that may land on a
#   healthier path.
# WHY-NOT: apt.conf.d Acquire::Retries alone — it only reopens a connection
#   after Acquire::http::Timeout fires, so it cannot recover from a trickle
#   that keeps the connection technically alive.
# WHY: `timeout` without `--kill-after` only sends SIGTERM once; apt-get
#   forks a separate http method worker to do the actual transfer, and if
#   that worker doesn't unwind promptly on SIGTERM, neither process actually
#   exits at the deadline — the retry loop never observes a return and stays
#   stuck on the first attempt. `--kill-after` guarantees a follow-up SIGKILL.
_apt_get_update() {
	if [[ -n "${DRY_RUN}" ]]; then
		_apt_get --yes update
		return 0
	fi
	local timeout_sec=300 kill_after_sec=10 max_attempts=3 attempt
	for ((attempt = 1; attempt <= max_attempts; attempt++)); do
		if timeout --kill-after="${kill_after_sec}" "${timeout_sec}" apt-get --yes update; then
			return 0
		fi
		log_warn "apt-get update timed out or failed (attempt ${attempt}/${max_attempts}), retrying"
	done
	log_erro "apt-get update failed after ${max_attempts} attempts"
	return 1
}

# --- Timezone ---
log_info "set Timezone: ${TZ}"
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime"
	echo "[DRY_RUN] echo ${TZ} > /etc/timezone"
else
	ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
	echo "${TZ}" > /etc/timezone
fi

# --- Remove container optimize configs ---
log_info "Remove container optimize"
for f in /etc/apt/apt.conf.d/docker-*; do
	if [[ -e "${f}" ]]; then
		if [[ -n "${DRY_RUN}" ]]; then
			echo "[DRY_RUN] rm ${f}"
		else
			rm "${f}"
		fi
	fi
done

# --- apt update / upgrade ---
log_info "apt update + upgrade"
_apt_get_update

# WHY-NOT: skip purge and let upgrade proceed — snapd is unused on the
#   bootstrap-provisioned VM target (no snap workloads shipped), and its
#   postinst pulls in loop-mounted squashfs images that only bloat the
#   deployed disk. Purging before upgrade keeps the image slim without
#   an extra cleanup pass over squashfs mounts.
# WHY-NOT: purge in 40-cleanup-ubuntu.sh — cleanup runs after apt upgrade,
#   by which point snapd has already installed its default snaps.
if [[ "${DEVTOOL_ENV}" == "vm" ]]; then
	log_info "vm: purge snapd before upgrade (image slimming)"
	_apt_get --yes purge snapd
fi

_apt_get --yes upgrade

# --- unminimize ---
log_info "unminimize"
_apt_get --yes install --no-install-recommends unminimize
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] yes | unminimize"
else
	{ yes 2>/dev/null || true; } | unminimize
fi

# --- apt install base packages ---
log_info "apt install base packages"
_apt_get --yes install --no-install-recommends \
	ca-certificates \
	command-not-found \
	libevent-dev \
	libncurses5-dev \
	man \
	man-db \
	openssh-client \
	pkg-config \
	software-properties-common \
	sudo \
	automake \
	bison \
	build-essential \
	bash \
	bash-completion \
	bind9-dnsutils \
	curl \
	git \
	gnupg \
	htop \
	iproute2 \
	iputils-arping \
	iputils-ping \
	iputils-tracepath \
	jq \
	less \
	lsof \
	mtr \
	nano \
	pv \
	rsync \
	socat \
	tcpdump \
	time \
	traceroute \
	unzip \
	vim \
	wget

log_info "10-apt-base.sh complete"
