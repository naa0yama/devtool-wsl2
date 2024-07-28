#- -----------------------------------------------------------------------------
#- - Global
#- -----------------------------------------------------------------------------
ARG DEBIAN_FRONTEND=noninteractive \
    \
    DEFAULT_USERNAME=user


#- -----------------------------------------------------------------------------
#- - Base
#- -----------------------------------------------------------------------------
FROM ubuntu:24.04 as base

ARG DEFAULT_UID=1100 \
    DEFAULT_GID=1100 \
    DEFAULT_USERNAME

ENV TZ=Asia/Tokyo

SHELL [ "/bin/bash", "-c" ]

# set Timezone
RUN set -eux && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN set -eux && \
    apt-get -y update && \
    apt-get -y upgrade && \
    yes | unminimize && \
    apt-get -y install --no-install-recommends \
    bash \
    ca-certificates \
    command-not-found \
    curl \
    git \
    gpg-agent \
    man \
    man-db \
    mtr \
    nano \
    software-properties-common \
    sudo \
    tcpdump \
    traceroute \
    unzip \
    vim \
    wget && \
    \
    # Cleanup \
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/*

# Create user
RUN set -eux && \
    groupadd --gid ${DEFAULT_GID} ${DEFAULT_USERNAME} && \
    useradd -s /bin/bash --uid ${DEFAULT_UID} --gid ${DEFAULT_GID} -m ${DEFAULT_USERNAME} && \
    echo ${DEFAULT_USERNAME}:password | chpasswd && \
    passwd -d ${DEFAULT_USERNAME} && \
    echo -e "${DEFAULT_USERNAME}\tALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEFAULT_USERNAME}

# Install Docker Engine
RUN set -eux && \
    # Add Docker's official GPG key: \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
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
    docker-compose-plugin && \
    usermod -aG docker "${DEFAULT_USERNAME}" && \
    \
    # Cleanup \
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/*

# Install fish-shell
RUN set -eux && \
    apt-add-repository -y ppa:fish-shell/release-3 && \
    apt-get -y update && \
    apt-get -y install --no-install-recommends \
    fish && \
    \
    # Cleanup \
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/*

USER ${DEFAULT_USERNAME}

# Install fish settings
RUN set -eux && \
    mkdir -p ~/.config/fish/completions && \
    ln -s ~/.asdf/completions/asdf.fish \
    ~/.config/fish/completions


#- -----------------------------------------------------------------------------
#- - User
#- -----------------------------------------------------------------------------
FROM base as user

ARG ASDF_VERSION=v0.14.0 \
    \
    DEBIAN_FRONTEND \
    DEFAULT_USERNAME

COPY --chown=${DEFAULT_USERNAME} --chmod=644 .tool-versions /home/${DEFAULT_USERNAME}/.tool-versions

# Install asdf
RUN set -eux && \
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf \
    --depth 1 --branch ${ASDF_VERSION} && \
    mkdir -p ~/.config/fish && \
    echo "source ~/.asdf/asdf.fish" > ~/.config/fish/config.fish && \
    echo ". \"\$HOME/.asdf/asdf.sh\"" >> ~/.bashrc && \
    echo ". \"\$HOME/.asdf/completions/asdf.bash\"" >> ~/.bashrc

# asdf update
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf update

# asdf install plugin asdf-assh
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add assh

# asdf install plugin awscli
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add awscli

# asdf install plugin fzf
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add fzf

# asdf install plugin ghq
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add ghq

# asdf install plugin terraform
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add terraform

# Dependencies Python
USER root
RUN set -eux && \
    apt-get -y update && \
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
    zlib1g-dev && \
    \
    # Cleanup \
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/*

# asdf install plugin python
USER ${DEFAULT_USERNAME}
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add python

# asdf install plugin poetry
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add poetry

# asdf install plugin rust
RUN set -eux && \
    echo -e "// cli-tools\ndua-cli\nripgrep\ntopgrade\n" > ~/.default-cargo-crates && \
    echo    "// install from source"                     >> ~/.default-cargo-crates && \
    echo    "// --git https://github.com/sharkdp/bat"    >> ~/.default-cargo-crates && \
    echo    ""                                           >> ~/.default-cargo-crates && \
    \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add rust

# asdf install plugin starship
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add starship

# asdf install plugin tmux
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add tmux

# asdf install plugin aws-sam-cli
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add aws-sam-cli

# plugin install
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf install python && \
    asdf install

# asdf check
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf current && \
    asdf list

# rust tools path append
RUN set -eux && \
    echo -e "#asdf rust command\nexport PATH=\$PATH:\$HOME/.asdf/installs/rust/stable/bin" >> ~/.bashrc && \
    source  ~/.bashrc

# rust tools path check
    RUN set -eux && \
    type -p dua && \
    type -p rg && \
    type -p topgrade

# WSL settings
## Ref: https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro
USER root
RUN set -x && \
    echo -e "[automount]\nenabled=true\nmountFsTab=true\nroot=\"/mnt/\"\noptions=\"metadata,uid=1000,gid=1000,umask=0022\"\n[user]\ndefault=${DEFAULT_USERNAME}\n[boot]\nsystemd=true" > /etc/wsl.conf

# remove container optimize
RUN set -eux && \
    rm /etc/apt/apt.conf.d/docker-*

USER ${DEFAULT_USERNAME}
WORKDIR /home/${DEFAULT_USERNAME}/
