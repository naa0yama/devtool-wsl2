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
FROM --platform=$BUILDPLATFORM ubuntu:noble-20260610@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90 AS base

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

COPY scripts			/opt/devtool
COPY .bashrc.d/devtool/	/opt/devtool/.bashrc.d/devtool/

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	/opt/devtool/provision/system/10-apt-base.sh

RUN /opt/devtool/provision/system/50-user.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	/opt/devtool/provision/system/20-docker-engine.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	/opt/devtool/provision/system/30-mise.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	/opt/devtool/provision/system/40-fish.sh

RUN DEVTOOL_ENV=wsl2 /opt/devtool/provision/system/60-wsl-conf.sh


#- -----------------------------------------------------------------------------
#- - User
#- -----------------------------------------------------------------------------
FROM base AS user

ARG DEBIAN_FRONTEND \
	DEFAULT_USERNAME

USER ${DEFAULT_USERNAME}

RUN /opt/devtool/provision/user/10-bashrc.sh
RUN /opt/devtool/provision/user/20-bashrc-devtool.sh
RUN /opt/devtool/provision/user/30-fish-config.sh

SHELL [ "/bin/bash", "-c" ]
USER ${DEFAULT_USERNAME}
WORKDIR /home/${DEFAULT_USERNAME}/
