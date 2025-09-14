#- -----------------------------------------------------------------------------
#- - Global
#- -----------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive \
	DEFAULT_USERNAME=user

## renovate: datasource=github-releases packageName=asdf-vm/asdf versioning=semver
ARG ASDF_VERSION="v0.18.0"
## renovate: datasource=github-releases packageName=edprint/dprint versioning=semver
ARG DPRINT_VERSION="0.50.0"
## renovate: datasource=github-releases packageName=mame/wsl2-ssh-agent versioning=semver
ARG WSL2SSHAGENT_VERSION="v0.9.6"

# retry dns and some http codes that might be transient errors
ARG CURL_OPTS="-sfSL --retry 3 --retry-delay 2 --retry-connrefused"


#- -----------------------------------------------------------------------------
#- - Base
#- -----------------------------------------------------------------------------
FROM ubuntu:24.04@sha256:9cbed754112939e914291337b5e554b07ad7c392491dba6daf25eef1332a22e8 AS base

ARG CURL_OPTS \
	DEFAULT_UID=1100 \
	DEFAULT_GID=1100 \
	DEFAULT_USERNAME \
	ASDF_VERSION \
	DPRINT_VERSION \
	WSL2SSHAGENT_VERSION

ENV TZ=Asia/Tokyo

SHELL [ "/bin/bash", "-c" ]

RUN echo "**** set Timezone ****" && \
	set -euxo pipefail && \
	ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

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
	gpg-agent \
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
echo "**** add 'asdf' to ~/.bashrc ****"
set -euxo pipefail

cat <<- _DOC_ >> ~/.bashrc

#asdf command
export PATH="\${ASDF_DATA_DIR:-$HOME/.asdf}/shims:\$PATH"
. <(asdf completion bash)

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

RUN echo "**** Install wsl2-ssh-agent ****" && \
	set -euxo pipefail && \
	__TEMPDIR=$(mktemp -d) && \
	cd ${__TEMPDIR} && \
	if [ -z "${WSL2SSHAGENT_VERSION}" ]; then echo "WSL2SSHAGENT_VERSION is blank"; else echo "WSL2SSHAGENT_VERSION is set to '$WSL2SSHAGENT_VERSION'"; fi && \
	curl ${CURL_OPTS} -O "$(curl ${CURL_OPTS} -H 'User-Agent: builder/1.0' \
	https://api.github.com/repos/mame/wsl2-ssh-agent/releases/tags/${WSL2SSHAGENT_VERSION} | \
	jq -r '.assets[] | select(.name | endswith("wsl2-ssh-agent")) | .browser_download_url')" && \
	curl ${CURL_OPTS} -O "$(curl ${CURL_OPTS} -H 'User-Agent: builder/1.0' \
	https://api.github.com/repos/mame/wsl2-ssh-agent/releases/tags/${WSL2SSHAGENT_VERSION} | \
	jq -r '.assets[] | select(.name | endswith("checksums.txt")) | .browser_download_url')" && \
	grep -E '\swsl2-ssh-agent$' checksums.txt | sha256sum --status -c - && \
	\
	cp -av wsl2-ssh-agent /usr/local/bin/wsl2-ssh-agent && \
	chmod +x /usr/local/bin/wsl2-ssh-agent && \
	type -p wsl2-ssh-agent && \
	rm -rf ${__TEMPDIR}

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

RUN echo "**** asdf install plugin asdf-assh ****" && \
	set -euxo pipefail && \
	asdf plugin add assh

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
	asdf install python && \
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

RUN <<EOF
echo "**** rust tools path append ****"
set -euxo pipefail && \

cat <<- _DOC_ >> ~/.bashrc
#asdf rust command
export PATH=\$PATH:\$HOME/.asdf/installs/rust/stable/bin

_DOC_
EOF

RUN echo "**** rust tools path check ****" && \
	set -euxo pipefail && \
	source ~/.bashrc && \
	type -p dua && \
	type -p rg && \
	type -p topgrade


#
RUN <<EOF
echo "**** Add restore dump and '.gitconfig' to ~/.bashrc ****"
set -euxo pipefail

cat <<- _DOC_ >> ~/.bashrc

# Restore dump
if [ ! -f "\${HOME}/.devtool-wsl2.lock" ]; then
	__WSL2_DIR="\$(wslpath -u \$(powershell.exe -c '\$env:USERPROFILE' | tr -d '\r'))/Documents/WSL2"
	__LAST_DUMP="\$(ls -t "\${__WSL2_DIR}/Backups/" | head -n1)"

	if [ -n "\${__LAST_DUMP}" ]; then
		echo "# =============================================================================="
		echo "# devtool-wsl2 restore tools"
		echo "#"
		echo "# WSL2 Directory: \"\${__WSL2_DIR}\""
		echo "# Last Dump     : \"\${__LAST_DUMP}\""
		echo "# =============================================================================="

		pv "\${__WSL2_DIR}/Backups/\${__LAST_DUMP}" | tar xf - -C "\${HOME}" --strip-components=2
		date '+%Y-%m-%dT%H%M%S%z' > "\${HOME}/.devtool-wsl2.lock"
		echo "Restore completed: \${__LAST_DUMP}"
	fi
fi

# Copy "~/.gitconfig" from Windows if it doesn't exist
if [ ! -f "\${HOME}/.gitconfig" ]; then
	__USERPROFILE="\$(wslpath -u \$(powershell.exe -c '\$env:USERPROFILE' | tr -d '\r'))"

	echo "Copy .gitconfig from Windows"
	cp -v "\${__USERPROFILE}/.gitconfig" ~/
fi
if [ ! -f "\${HOME}/.gitignore_global" ]; then
	__USERPROFILE="\$(wslpath -u \$(powershell.exe -c '\$env:USERPROFILE' | tr -d '\r'))"

	echo "Copy .gitignore_global from Windows"
	cp -v "\${__USERPROFILE}/.gitignore_global" ~/
fi

_DOC_
EOF

USER root
RUN <<EOF
echo "**** Add 'backup.sh' to /usr/local/bin ****"
set -euxo pipefail

cat <<- _DOC_ >> /usr/local/bin/backup.sh
#!/usr/bin/env bash
set -eu

WSL2_DIR="\$(wslpath -u \$(powershell.exe -c '\$env:USERPROFILE' | tr -d '\r'))/Documents/WSL2"
FILENAME_DUMP="\$(date '+%Y-%m-%dT%H%M%S')_devtool-wsl2.tar"
EXCLUDE_DIRS=(
	".asdf"
	".cache"
	".docker"
	".dotnet"
	".local"
	".vscode-remote-containers"
	".vscode-server"
)

EXCLUDE_ARGS=()
for dir in "\${EXCLUDE_DIRS[@]}"; do
	EXCLUDE_ARGS+=("--exclude=\${dir}")
done

cat <<__EOF__> /dev/stdout
# ==============================================================================
# devtool-wsl2 backup tools
#
# WSL2 Directory: "\${WSL2_DIR}"
# Filename      : "\${FILENAME_DUMP}"
# Excludes      : "\${EXCLUDE_ARGS[@]}"
# ==============================================================================

__EOF__

echo "Calculating directory size..."
TOTAL_SIZE=\$(du -sb "\${HOME}" \
	"\${EXCLUDE_ARGS[@]}" \
	2>/dev/null | cut -f1)

echo "Starting backup: \$(numfmt --to=iec \${TOTAL_SIZE}) to compress"
tar -c \
	"\${EXCLUDE_ARGS[@]}" \
	"\${HOME}" | pv -p -t -e -r -a -s "\${TOTAL_SIZE}" > "/tmp/\${FILENAME_DUMP}"

mkdir -p "\${WSL2_DIR}/Backups"
rsync -avP "/tmp/\${FILENAME_DUMP}" "\${WSL2_DIR}/Backups"
echo "Backup completed: \${WSL2_DIR}/Backups/\${FILENAME_DUMP}"

_DOC_

chmod +x /usr/local/bin/backup.sh

EOF
USER ${DEFAULT_USERNAME}

# wsl2-ssh-agent Config
RUN <<EOF
echo "**** Add 'wsl2-ssh-agent config' to ~/.bashrc ****"
set -euxo pipefail

cat <<- _DOC_ >> ~/.bashrc

# Bash configuration for wsl2-ssh-agent
eval \$(/usr/local/bin/wsl2-ssh-agent)

_DOC_

mkdir -p ~/.ssh
chmod 0700 ~/.ssh

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

RUN echo "**** Remove container optimize ****" && \
	set -euxo pipefail && \
	rm /etc/apt/apt.conf.d/docker-*

USER ${DEFAULT_USERNAME}
WORKDIR /home/${DEFAULT_USERNAME}/
