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
    apt -y update && \
    apt -y upgrade && \
    yes | unminimize && \
    apt -y install --no-install-recommends \
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
    apt -y autoremove && \
    apt -y clean && \
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
    apt -y update && \
    apt -y install --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin && \
    usermod -aG docker "${DEFAULT_USERNAME}" && \
    \
    # Cleanup \
    apt -y autoremove && \
    apt -y clean && \
    rm -rf /var/lib/apt/lists/*

# Install fish-shell
RUN set -eux && \
    apt-add-repository -y ppa:fish-shell/release-3 && \
    apt -y update && \
    apt -y install --no-install-recommends \
    fish && \
    \
    # Cleanup \
    apt -y autoremove && \
    apt -y clean && \
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
    ASDF_PLUGIN_ASSH_VER=2.16.0 \
    ASDF_PLUGIN_AWSCLI_VER=2.15.19 \
    ASDF_PLUGIN_FZF_VER=0.50.0 \
    ASDF_PLUGIN_GHQ_VER=1.6.1 \
    ASDF_PLUGIN_POETRY_VER=1.7.1 \
    ASDF_PLUGIN_PYTHON_VER=3.10.12 \
    ASDF_PLUGIN_RUST_VER=stable \
    ASDF_PLUGIN_SAM_CLI_VER=1.115.0 \
    ASDF_PLUGIN_STARSHIP_VER=1.18.2 \
    ASDF_PLUGIN_TERRAFORM_VER=1.1.3 \
    ASDF_PLUGIN_TMUX_VER=3.4 \
    \
    DEBIAN_FRONTEND \
    DEFAULT_USERNAME

# Install asdf
RUN set -eux && \
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf \
    --depth 1 --branch ${ASDF_VERSION} && \
    mkdir -p ~/.config/fish && \
    echo "source ~/.asdf/asdf.fish" > ~/.config/fish/config.fish && \
    echo ". \"\$HOME/.asdf/asdf.sh\"" >> ~/.bashrc && \
    echo ". \"\$HOME/.asdf/completions/asdf.bash\"" >> ~/.bashrc

# asdf install plugin asdf-assh
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add assh && \
    asdf install assh ${ASDF_PLUGIN_ASSH_VER} && \
    asdf global assh ${ASDF_PLUGIN_ASSH_VER}

# asdf install plugin awscli
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add awscli && \
    asdf install awscli ${ASDF_PLUGIN_AWSCLI_VER} && \
    asdf global awscli ${ASDF_PLUGIN_AWSCLI_VER}

# asdf install plugin fzf
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add fzf && \
    asdf install fzf ${ASDF_PLUGIN_FZF_VER} && \
    asdf global fzf ${ASDF_PLUGIN_FZF_VER}

# asdf install plugin ghq
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add ghq && \
    asdf install ghq ${ASDF_PLUGIN_GHQ_VER} && \
    asdf global ghq ${ASDF_PLUGIN_GHQ_VER}

# asdf install plugin terraform
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add terraform && \
    asdf install terraform ${ASDF_PLUGIN_TERRAFORM_VER} && \
    asdf global terraform ${ASDF_PLUGIN_TERRAFORM_VER}

# Dependencies Python
USER root
RUN set -eux && \
    apt -y update && \
    apt install -y --no-install-recommends \
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
    apt -y autoremove && \
    apt -y clean && \
    rm -rf /var/lib/apt/lists/*

# asdf install plugin python
USER ${DEFAULT_USERNAME}
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add python && \
    asdf install python ${ASDF_PLUGIN_PYTHON_VER} && \
    asdf global python ${ASDF_PLUGIN_PYTHON_VER}

# asdf install plugin poetry
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add poetry && \
    asdf install poetry ${ASDF_PLUGIN_POETRY_VER} && \
    asdf global poetry ${ASDF_PLUGIN_POETRY_VER}

# asdf install plugin rust
RUN set -eux && \
    echo -e "// cli-tools\ndua-cli\nripgrep\ntopgrade\n" > ~/.default-cargo-crates && \
    echo    "// install from source"                     >> ~/.default-cargo-crates && \
    echo    "// --git https://github.com/sharkdp/bat"    >> ~/.default-cargo-crates && \
    echo    ""                                           >> ~/.default-cargo-crates && \
    \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add rust && \
    asdf install rust ${ASDF_PLUGIN_RUST_VER} && \
    asdf global rust ${ASDF_PLUGIN_RUST_VER} && \
    echo -e "#asdf rust command\nexport PATH=\$PATH:\$HOME/.asdf/installs/rust/stable/bin" >> ~/.bashrc && \
    source  ~/.bashrc && \
    type -p dua && \
    type -p rg && \
    type -p topgrade

# asdf install plugin starship
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add starship && \
    asdf install starship ${ASDF_PLUGIN_STARSHIP_VER} && \
    asdf global starship ${ASDF_PLUGIN_STARSHIP_VER}

# asdf install plugin tmux
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add tmux && \
    asdf install tmux ${ASDF_PLUGIN_TMUX_VER} && \
    asdf global tmux ${ASDF_PLUGIN_TMUX_VER}

# asdf install plugin aws-sam-cli
RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf plugin-add aws-sam-cli && \
    asdf install aws-sam-cli ${ASDF_PLUGIN_SAM_CLI_VER} && \
    asdf global aws-sam-cli ${ASDF_PLUGIN_SAM_CLI_VER}

RUN set -eux && \
    source $HOME/.asdf/asdf.sh && \
    asdf current  && \
    asdf list

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
