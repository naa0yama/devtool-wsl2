#!/usr/bin/env bash
set -euo pipefail
[[ -n "${DEVTOOL_TRACE:-}" ]] && set -x

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

TZ="${TZ:-Asia/Tokyo}"
DRY_RUN="${DRY_RUN:-}"

_apt_get() {
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] apt-get $*"
	else
		apt-get "$@"
	fi
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
_apt_get --yes update
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
