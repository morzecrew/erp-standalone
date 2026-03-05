# syntax=docker/dockerfile-upstream:1.4.0
FROM debian:stable-slim
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# PORTER_INIT

RUN rm -f /etc/apt/apt.conf.d/docker-clean \
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gpg \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/provision.sh /tmp/provision.sh

ARG JUST_VERSION=""
ENV JUST_VERSION=${JUST_VERSION}

RUN chmod +x /tmp/provision.sh \
    && /tmp/provision.sh \
    && rm -f /tmp/provision.sh

# PORTER_MIXINS

# Copy only the bundle payload into the CNAB working dir
COPY ./stack ${BUNDLE_DIR}
COPY ./porter.yaml ${BUNDLE_DIR}
COPY ./scaffold /scaffold

RUN chmod -R a+rwX /scaffold