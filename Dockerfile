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

## renovate: datasource=github-releases packageName=asdf-vm/asdf versioning=semver automerge=true
ARG ASDF_VERSION="v0.18.0"
## renovate: datasource=github-releases packageName=edprint/dprint versioning=semver automerge=true
ARG DPRINT_VERSION="0.50.0"

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
	DEFAULT_USERNAME \
	ASDF_VERSION \
	DPRINT_VERSION

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
	automake \
	bash \
	bash-completion \
	bind9-dnsutils \
	bison \
	build-essential \
	ca-certificates \
	command-not-found \
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
	libevent-dev \
	libncurses5-dev \
	lsof \
	man \
	man-db \
	mtr \
	nano \
	openssh-client \
	pkg-config \
	pv \
	rsync \
	socat \
	software-properties-common \
	sudo \
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
	# Add Docker's official GPG key: \
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
	echo "**** Install dprint ****" && \
	set -euxo pipefail && \
	_download_url="$(curl ${CURL_OPTS} -H 'User-Agent: builder/1.0' \
	https://api.github.com/repos/dprint/dprint/releases/tags/${DPRINT_VERSION} | \
	jq -r '.assets[] | select(.name | endswith("x86_64-unknown-linux-gnu.zip")) | .browser_download_url')" && \
	_filename="$(basename "$_download_url")" && \
	curl ${CURL_OPTS} -H 'User-Agent: builder/1.0' -o "./${_filename}" "${_download_url}" && \
	unzip "${_filename}" -d /usr/local/bin/ && \
	type -p dprint && \
	rm -rf "./${_filename}"

RUN echo "**** Install git-secrets ****" && \
	set -euxo pipefail && \
	cd /tmp && \
	git clone --depth 1 https://github.com/awslabs/git-secrets.git && \
	cd git-secrets && \
	make install && \
	type -p /usr/local/bin/git-secrets && \
	rm -rf /tmp/git-secrets

USER ${DEFAULT_USERNAME}


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

cat <<- _DOC_ >> ~/.bashrc

# Include ~/.bashrc.d/devtool/
if [ -d ~/.bashrc.d/devtool ]; then
	for f in ~/.bashrc.d/devtool/*.sh; do
		[ -r "\$f" ] && source "\$f"
	done
fi

_DOC_
EOF

RUN <<EOF
echo "**** Add ~/.bashrc.d/devtool/05-path.sh ****"
set -euxo pipefail

mkdir -p ~/.local/bin ~/.bashrc.d/devtool
cat <<- _DOC_ > ~/.bashrc.d/devtool/05-path.sh
#!/usr/bin/env bash

# Add PATH .loca./bin
case ":\$PATH:" in
	*":\$HOME/.local/bin:"*) ;;
	*) export PATH="\$HOME/.local/bin:\$PATH" ;;
esac

_DOC_
EOF

RUN <<EOF
echo "**** Add ~/.bashrc.d/devtool/10-mise.sh ****"
set -euxo pipefail

cat <<- _DOC_ > ~/.bashrc.d/devtool/10-mise.sh
#!/usr/bin/env bash

eval "\$(mise activate bash)"

# This requires bash-completion to be installed
if [ ! -f "~/.local/share/bash-completion/completions/mise" ]; then
	mkdir -p ~/.local/share/bash-completion/completions/
	mise completion bash --include-bash-completion-lib > ~/.local/share/bash-completion/completions/mise
fi

_DOC_
EOF


RUN <<EOF
echo "**** Add ~/.bashrc.d/devtool/11-devtool-wsl2.sh ****"
set -euxo pipefail

cat <<- _DOC_ > ~/.bashrc.d/devtool/11-devtool-wsl2.sh
#!/usr/bin/env bash

# Restore dump
if [ ! -f "\${HOME}/.dwsl2-restore.lock" ]; then
	/opt/devtool/bin/restore.sh
fi

# Setup
if [ ! -f "\${HOME}/.cache/devtool-setup.lock" ]; then
	/opt/devtool/bin/setup.sh
fi

_DOC_
EOF

RUN <<EOF
echo "**** Add ~/.bashrc.d/devtool/31-gitconfig-copy.sh ****"
set -euxo pipefail

cat <<- _DOC_ > ~/.bashrc.d/devtool/31-gitconfig-copy.sh
#!/usr/bin/env bash

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m \$*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m \$*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m \$*" >&2; }

# Env
USERPROFILE="\$(wslpath -u \$(powershell.exe -c '\$env:USERPROFILE' | tr -d '\r'))"

# Copy "~/.gitconfig" from Windows if it doesn't exist
# File
if [ ! -f "\${HOME}/.gitconfig" -a -f "\${USERPROFILE}/.gitconfig" ]; then
	log_info "Copy .gitconfig from Windows"
	cp -v "\${USERPROFILE}/.gitconfig" ~/
	chmod 0644 "\${HOME}/.gitconfig"
fi
if [ ! -f "\${HOME}/.gitignore_global" -a -f "\${USERPROFILE}/.gitignore_global" ]; then
	log_info "Copy .gitignore_global from Windows"
	cp -v "\${USERPROFILE}/.gitignore_global" ~/
	chmod 0644 "\${HOME}/.gitignore_global"
fi

# Directory
if [ ! -d "\${HOME}/.gitconfig.d" -a -d "\${USERPROFILE}/.gitconfig.d" ]; then
	log_info "Copy .gitconfig.d from Windows"
	cp -Rv "\${USERPROFILE}/.gitconfig.d" ~/
	find "\${HOME}/.gitconfig.d" -type d -exec chmod 0755 {} \;
	find "\${HOME}/.gitconfig.d" -type f -exec chmod 0644 {} \;
fi

_DOC_
EOF

RUN mkdir -p ~/.config/mise
COPY --chown=${DEFAULT_USERNAME} --chmod=644 mise.toml /home/${DEFAULT_USERNAME}/.config/mise/config.toml
RUN mise install && \
	mise ls

RUN echo "**** rust tools path check ****" && \
	set -euxo pipefail && \
	source ~/.bashrc && \
	type -p dua && \
	type -p rg && \
	type -p topgrade

USER root
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

COPY --chown=${DEFAULT_USERNAME}:${DEFAULT_USERNAME}	scripts		/opt/devtool
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
USER root
RUN <<EOF
echo "**** WSL settings ****"
set -euxo pipefail

cat <<- _DOC_ > /etc/wsl.conf
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

SHELL [ "/bin/bash", "-c" ]
USER ${DEFAULT_USERNAME}
WORKDIR /home/${DEFAULT_USERNAME}/
