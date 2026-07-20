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

COPY scripts			/opt/devtool/scripts

# WHY-NOT: RUN 個別行維持 — 新 script 追加時に Dockerfile 修正が必要になる
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
	--mount=type=cache,target=/var/lib/apt,sharing=locked \
	for f in /opt/devtool/scripts/provision/system/*.sh; do \
		DEVTOOL_ENV=wsl2 PROVISION_ROOT=/opt/devtool/scripts/provision bash "${f}"; \
	done


#- -----------------------------------------------------------------------------
#- - User
#- -----------------------------------------------------------------------------
FROM base AS user

ARG DEBIAN_FRONTEND \
	DEFAULT_USERNAME

USER ${DEFAULT_USERNAME}

# WHY-NOT: RUN 個別行維持 — 新 script 追加時に Dockerfile 修正が必要になる
RUN for f in /opt/devtool/scripts/provision/user/*.sh; do \
		DEVTOOL_ENV=wsl2 PROVISION_ROOT=/opt/devtool/scripts/provision bash "${f}"; \
	done

SHELL [ "/bin/bash", "-c" ]
USER ${DEFAULT_USERNAME}
WORKDIR /home/${DEFAULT_USERNAME}/
