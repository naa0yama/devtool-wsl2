#- -----------------------------------------------------------------------------
#- - Global
#- -----------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive \
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

ARG CURL_OPTS \
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

RUN echo "**** Install asdf ****" && \
	set -euxo pipefail && \
	cd /tmp && \
	if [ -z "${ASDF_VERSION}" ]; then echo "ASDF_VERSION is blank"; else echo "ASDF_VERSION is set to '$ASDF_VERSION'"; fi && \
	curl ${CURL_OPTS} -o /tmp/asdf.tar.gz "$(curl -sfSL -H 'User-Agent: builder/1.0' \
	https://api.github.com/repos/asdf-vm/asdf/releases/tags/${ASDF_VERSION} | \
	jq -r '.assets[] | select(.name | endswith("linux-amd64.tar.gz")) | .browser_download_url')" && \
	tar -xf /tmp/asdf.tar.gz && \
	mv -v /tmp/asdf /usr/local/bin/asdf && \
	type -p asdf && \
	asdf version

USER ${DEFAULT_USERNAME}
RUN <<EOF
echo "**** add '~/.bashrc.d/*.sh' to ~/.bashrc ****"
set -euxo pipefail

cat <<- _DOC_ >> ~/.bashrc

# Include ~/.bashrc.d/
if [ -d ~/.bashrc.d ]; then
	for f in ~/.bashrc.d/*.sh; do
		[ -r "\$f" ] && source "\$f"
	done
fi

_DOC_
EOF

RUN <<EOF
echo "**** add 'asdf' to ~/.bashrc.d/10-asdf.sh ****"
set -euxo pipefail

mkdir -p ~/.bashrc.d/
cat <<- _DOC_ > ~/.bashrc.d/10-asdf.sh
#!/usr/bin/env bash

# asdf command
export PATH="\${ASDF_DATA_DIR:-\$HOME/.asdf}/shims:\$PATH"
. <(asdf completion bash)

# asdf rust command
export PATH=\$PATH:\$HOME/.asdf/installs/rust/stable/bin

_DOC_
EOF

USER root

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

COPY --chown=${DEFAULT_USERNAME} --chmod=644 .tool-versions /home/${DEFAULT_USERNAME}/.tool-versions

RUN echo "**** asdf install plugin awscli ****" && \
	set -euxo pipefail && \
	asdf plugin add awscli

RUN echo "**** asdf install plugin fzf ****" && \
	set -euxo pipefail && \
	asdf plugin add fzf

RUN echo "**** asdf install plugin ghq ****" && \
	set -euxo pipefail && \
	asdf plugin add ghq

RUN echo "**** asdf install plugin terraform ****" && \
	set -euxo pipefail && \
	asdf plugin add terraform

USER root
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	\
	echo "**** Dependencies Python ****" && \
	set -euxo pipefail && \
	apt-get update && \
	apt-get install -y --no-install-recommends \
	build-essential \
	libbz2-dev \
	libffi-dev \
	liblzma-dev \
	libncursesw5-dev \
	libreadline-dev \
	libsqlite3-dev \
	libssl-dev \
	libxml2-dev \
	libxmlsec1-dev \
	tk-dev \
	xz-utils \
	zlib1g-dev

USER ${DEFAULT_USERNAME}
RUN echo "**** asdf install plugin python ****" && \
	set -euxo pipefail && \
	asdf plugin add python

RUN echo "**** asdf install plugin poetry ****" && \
	set -euxo pipefail && \
	asdf plugin add poetry

RUN echo "**** asdf install plugin rust ****" && \
	set -euxo pipefail && \
	echo -e "// cli-tools\ndua-cli\nripgrep\ntopgrade\n" >  ~/.default-cargo-crates && \
	echo    "// install from source"                     >> ~/.default-cargo-crates && \
	echo    "// --git https://github.com/sharkdp/bat"    >> ~/.default-cargo-crates && \
	echo    ""                                           >> ~/.default-cargo-crates && \
	\
	asdf plugin add rust

RUN echo "**** asdf install plugin starship ****" && \
	set -euxo pipefail && \
	asdf plugin add starship

RUN echo "**** asdf install plugin tmux ****" && \
	set -euxo pipefail && \
	asdf plugin add tmux

RUN echo "**** asdf install plugin aws-sam-cli ****" && \
	set -euxo pipefail && \
	asdf plugin add aws-sam-cli

RUN echo "**** asdf install python ****" && \
	set -euxo pipefail && \
	asdf install python

RUN echo "**** asdf install other deps ****" && \
	set -euxo pipefail && \
	asdf install

RUN echo "**** asdf check ****" && \
	set -euxo pipefail && \
	asdf current && \
	asdf list

ARG PATH="/home/${DEFAULT_USERNAME}/.asdf/shims:${PATH}"
RUN <<EOF
echo "**** asdf check ****"
set -euxo pipefail && \

cat ~/.tool-versions | cut -d " " -f 1 | while read line
do
    case ${line} in
    "aws-sam-cli")
        type -p sam
    ;;
    "awscli")
        type -p aws
    ;;
    "rust")
        type -p cargo
    ;;
    *)
        type -p ${line}
    ;;
    esac
done

EOF

RUN echo "**** rust tools path check ****" && \
	set -euxo pipefail && \
	source ~/.bashrc && \
	type -p dua && \
	type -p rg && \
	type -p topgrade

RUN <<EOF
echo "**** Add ~/.bashrc.d/05-path.sh ****"
set -euxo pipefail

mkdir -p $HOME/.local/bin
cat <<- _DOC_ > ~/.bashrc.d/05-path.sh
#!/usr/bin/env bash

# Add PATH .loca./bin
case ":\$PATH:" in
	*":\$HOME/.local/bin:"*) ;;
	*) export PATH="\$HOME/.local/bin:\$PATH" ;;
esac

_DOC_
EOF

RUN <<EOF
echo "**** Add ~/.bashrc.d/11-devtool-wsl2.sh ****"
set -euxo pipefail

cat <<- _DOC_ > ~/.bashrc.d/11-devtool-wsl2.sh
#!/usr/bin/env bash

# Setup
if [ ! -f "\${HOME}/.cache/devtool-setup.lock" ]; then
	\$HOME/.local/bin/setup.sh
fi

# Restore dump
if [ ! -f "\${HOME}/.dwsl2-restore.lock" ]; then
	\$HOME/.local/bin/restore.sh
fi

_DOC_
EOF

RUN <<EOF
echo "**** Add ~/.bashrc.d/31-gitconfig-copy.sh ****"
set -euxo pipefail

cat <<- _DOC_ > ~/.bashrc.d/31-gitconfig-copy.sh
#!/usr/bin/env bash

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# Copy "~/.gitconfig" from Windows if it doesn't exist
if [ ! -f "\${HOME}/.gitconfig" ]; then
	__USERPROFILE="\$(wslpath -u \$(powershell.exe -c '\$env:USERPROFILE' | tr -d '\r'))"

	log_info "Copy .gitconfig from Windows"
	cp -v "\${__USERPROFILE}/.gitconfig" ~/
fi
if [ ! -f "\${HOME}/.gitconfig.d" ]; then
	__USERPROFILE="\$(wslpath -u \$(powershell.exe -c '\$env:USERPROFILE' | tr -d '\r'))"

	log_info "Copy .gitconfig.d from Windows"
	cp -Rv "\${__USERPROFILE}/.gitconfig.d" ~/
fi
if [ ! -f "\${HOME}/.gitignore_global" ]; then
	__USERPROFILE="\$(wslpath -u \$(powershell.exe -c '\$env:USERPROFILE' | tr -d '\r'))"

	log_info "Copy .gitignore_global from Windows"
	cp -v "\${__USERPROFILE}/.gitignore_global" ~/
fi

_DOC_
EOF

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

COPY --chown=${DEFAULT_USERNAME}:${DEFAULT_USERNAME}	scripts/bin/setup.sh		/home/${DEFAULT_USERNAME}/.local/bin/setup.sh
COPY --chown=${DEFAULT_USERNAME}:${DEFAULT_USERNAME}	scripts/bin/yubikey-tool.ps1	/home/${DEFAULT_USERNAME}/.local/bin/yubikey-tool.ps1
COPY --chown=${DEFAULT_USERNAME}:${DEFAULT_USERNAME}	scripts/bin/restore.sh		/home/${DEFAULT_USERNAME}/.local/bin/restore.sh
COPY --chown=${DEFAULT_USERNAME}:${DEFAULT_USERNAME}	scripts/bin/backup.sh		/home/${DEFAULT_USERNAME}/.local/bin/backup.sh

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

USER ${DEFAULT_USERNAME}
WORKDIR /home/${DEFAULT_USERNAME}/
