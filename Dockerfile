#- -----------------------------------------------------------------------------
#- - Global
#- -----------------------------------------------------------------------------
ARG BUILD_ACTION="${BUILD_ACTION:-unknown}" \
	BUILD_BASE_REF="${BUILD_BASE_REF:-unknown}" \
	BUILD_REPOSITORY="${BUILD_REPOSITORY:-unknown}" \
	BUILD_SHA="${BUILD_SHA:-unknown}" \
	\
	DEBIAN_FRONTEND=noninteractive \
	DEFAULT_USERNAME=user

# retry dns and some http codes that might be transient errors
ARG CURL_OPTS="-sfSL --retry 3 --retry-delay 2 --retry-connrefused"


#- -----------------------------------------------------------------------------
#- - Base
#- -----------------------------------------------------------------------------
FROM ubuntu:24.04@sha256:66460d557b25769b102175144d538d88219c077c678a49af4afca6fbfc1b5252 AS base

ARG BUILD_ACTION \
	BUILD_BASE_REF \
	BUILD_REPOSITORY \
	BUILD_SHA \
	\
	CURL_OPTS \
	DEBIAN_FRONTEND \
	DEFAULT_UID=1100 \
	DEFAULT_GID=1100 \
	DEFAULT_USERNAME

ENV TZ=Asia/Tokyo

SHELL [ "/bin/bash", "-c" ]

RUN echo "**** set Timezone ****" && \
	set -euxo pipefail && \
	ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN echo "**** Remove container optimize ****" && \
	set -euxo pipefail && \
	rm /etc/apt/apt.conf.d/docker-*

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	\
	echo "**** Dependencies ****" && \
	set -eux && \
	apt-get -y update && \
	apt-get -y upgrade && \
	apt-get -y install --no-install-recommends unminimize && \
	yes | unminimize && \
	apt-get -y install --no-install-recommends \
	# System utils
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
	# Development tools
	automake \
	bison \
	build-essential \
	# CLI tools
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

RUN echo "**** Create user ****" && \
	set -euxo pipefail && \
	userdel --remove ubuntu && \
	\
	groupadd --gid ${DEFAULT_GID} ${DEFAULT_USERNAME} && \
	useradd -s /bin/bash --uid ${DEFAULT_UID} --gid ${DEFAULT_GID} -m ${DEFAULT_USERNAME} && \
	echo ${DEFAULT_USERNAME}:password | chpasswd && \
	passwd -d ${DEFAULT_USERNAME} && \
	echo -e "${DEFAULT_USERNAME}\tALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEFAULT_USERNAME}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	\
	echo "**** Install Docker Engine ****" && \
	set -euxo pipefail && \
	install -m 0755 -d /etc/apt/keyrings && \
	curl ${CURL_OPTS} https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
	chmod a+r /etc/apt/keyrings/docker.asc && \
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
	https://download.docker.com/linux/ubuntu \
	$(. /etc/os-release && echo "${VERSION_CODENAME}") stable" | \
	tee /etc/apt/sources.list.d/docker.list > /dev/null && \
	apt-get -y update && \
	apt-get -y install --no-install-recommends \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin \
	&& \
	usermod -aG docker "${DEFAULT_USERNAME}"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	\
	echo "**** Install mise ****" && \
	set -euxo pipefail && \
	install -dm 755 /etc/apt/keyrings && \
	curl -fSs https://mise.jdx.dev/gpg-key.pub | \
	tee /etc/apt/keyrings/mise-archive-keyring.pub 1> /dev/null && \
	echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.pub arch=amd64] https://mise.jdx.dev/deb stable main" | \
	tee /etc/apt/sources.list.d/mise.list && \
	apt-get update && \
	apt-get -y install --no-install-recommends \
	mise \
	&& \
	type -p mise

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	\
	echo "**** Install fish ****" && \
	set -euxo pipefail && \
	add-apt-repository ppa:fish-shell/release-4 && \
	apt-get update && \
	apt-get -y install --no-install-recommends \
	fish \
	&& \
	type -p fish

RUN <<EOF
echo "**** systemctl mask gpg-agent* ****"
set -euxo pipefail

mkdir -p /etc/systemd/user
ln -sf /dev/null /etc/systemd/user/gpg-agent.socket
ln -sf /dev/null /etc/systemd/user/gpg-agent-browser.socket
ln -sf /dev/null /etc/systemd/user/gpg-agent-extra.socket
ln -sf /dev/null /etc/systemd/user/gpg-agent-ssh.socket
ln -sf /dev/null /etc/systemd/user/gpg-agent.service

EOF

RUN <<EOF
echo "**** Add /etc/devtool-release ****"
set -euxo pipefail

cat <<- _DOC_ > /etc/devtool-release
BUILD_REPOSITORY="${BUILD_REPOSITORY}"
BUILD_BASE_REF="${BUILD_BASE_REF}"
BUILD_DATE="$(date +%Y-%m-%dT%H:%M:%S%z)"
BUILD_ACTION="${BUILD_ACTION}"
BUILD_SHA="${BUILD_SHA}"
_DOC_
sed -i 's/^[[:space:]]*//' /etc/devtool-release
EOF

## Ref: https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro
RUN <<EOF
echo "**** WSL settings ****"
set -euxo pipefail

cat <<- '_DOC_' > /etc/wsl.conf
[automount]
enabled=true
mountFsTab=true
root="/mnt/"
options="metadata,uid=${DEFAULT_UID},gid=${DEFAULT_GID},umask=0022"

[user]
default=${DEFAULT_USERNAME}

[boot]
systemd=true

_DOC_
EOF


#- -----------------------------------------------------------------------------
#- - User
#- -----------------------------------------------------------------------------
FROM base AS user

ARG DEBIAN_FRONTEND \
	DEFAULT_USERNAME

USER ${DEFAULT_USERNAME}
RUN <<EOF
echo "**** add '~/.bashrc.d/devtool/*.sh' to ~/.bashrc ****"
set -euxo pipefail

cat <<- '_DOC_' >> ~/.bashrc

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
    exec fish
fi

_DOC_
EOF

RUN echo "**** Copy ~/.bashrc.d/devtool ****" && \
	set -euxo pipefail && \
	mkdir -p ~/.local/bin ~/.bashrc.d/devtool
COPY --chown=${DEFAULT_USERNAME} --chmod=644 .bashrc.d/devtool/	/home/${DEFAULT_USERNAME}/.bashrc.d/devtool

RUN echo "**** Create Directory ~/.config/mise ****" && \
	set -euxo pipefail && \
	mkdir -p ~/.config/mise

RUN <<EOF
echo "**** add fisher and fish_prompt.fish ****"
set -euxo pipefail

mkdir -p ~/.config/fish/functions
curl -sfSL -o ~/.config/fish/functions/fisher.fish \
	https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish

cat <<- '_DOC_' > ~/.config/fish/config.fish
#!/usr/bin/env fish

# mise
/bin/mise activate fish | source

_DOC_

cat <<- '_DOC_' > ~/.config/fish/functions/fish_prompt.fish
#!/usr/bin/env fish

function fish_prompt
	set_color green
	echo -n (prompt_pwd)
	set_color normal
	echo -n '> '
end

_DOC_
EOF

#- -----------------------------------------------------------------------------
#- - Runer
#- -----------------------------------------------------------------------------
COPY --chown=${DEFAULT_USERNAME}:${DEFAULT_USERNAME}	scripts		/opt/devtool
SHELL [ "/bin/bash", "-c" ]
USER ${DEFAULT_USERNAME}
WORKDIR /home/${DEFAULT_USERNAME}/
