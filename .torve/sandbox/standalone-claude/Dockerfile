# This repository's claude seat: torve's published claude seat image, plus the
# tools `.torve/gates.yaml` names and the bundle's phases run. An attempt's
# battery and the lane's run in the executor seat's image, so the gate tools live
# in the seat. The docker CLI, buildx and compose come from the base, on the
# version of the nested daemon; `edge-smoke` drives the task's nested daemon
# through `DOCKER_HOST`. Every download is pinned by version and checked: morzer
# by its release signature and checksum, the rest by a sha256 read off each
# release's checksum file (zizmor publishes none: its pin is the archive's hash
# on 2026-10-23). amd64 only, as the host is.
#
#   docker build -t standalone-claude-sandbox:2.1.283-torve0.7.0 .torve/sandbox/standalone-claude
ARG BASE=ghcr.io/morzecrew/claude-sandbox:2.1.283-torve0.7.0
FROM ${BASE}

ARG MORZER=0.7.0
# `morzer.pub` at the root of morzecrew/morzer, as its install.sh carries it.
ARG MORZER_PUBKEY=RWRS3ZHbN8tEYuF9Se2e+JzQMiUCoLbABbJtzSxBThI/U4Bhw+AR+IbQ
ARG YQ=4.54.1
ARG YQ_SHA256=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f
ARG ORAS=1.3.5
ARG ORAS_SHA256=f48a73ea6d026a862c3919fc773da9a8c86fc259c2c737d5baed3b8b9614ad22
ARG ACTIONLINT=1.7.12
ARG ACTIONLINT_SHA256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
ARG ZIZMOR=1.31.1
ARG ZIZMOR_SHA256=d185f726bdaf92df78273217dfdd24ebcd6b0ef48cf3ce776ff5762b6e138c99
ARG SOPS=3.13.3
ARG SOPS_SHA256=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
 && apt-get install -y --no-install-recommends shellcheck minisign age jq \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/seat
RUN gh=https://github.com \
 && curl -fsSLO "${gh}/morzecrew/morzer/releases/download/v${MORZER}/morzer_${MORZER}_linux_amd64.tar.zst" \
 && curl -fsSLO "${gh}/morzecrew/morzer/releases/download/v${MORZER}/SHA256SUMS" \
 && curl -fsSLO "${gh}/morzecrew/morzer/releases/download/v${MORZER}/SHA256SUMS.minisig" \
 && minisign -Vm SHA256SUMS -P "${MORZER_PUBKEY}" \
 && grep " morzer_${MORZER}_linux_amd64.tar.zst\$" SHA256SUMS | sha256sum -c - \
 && tar --zstd -xf "morzer_${MORZER}_linux_amd64.tar.zst" morzer \
 && install -m 0755 morzer /usr/local/bin/morzer \
 && curl -fsSL -o yq "${gh}/mikefarah/yq/releases/download/v${YQ}/yq_linux_amd64" \
 && echo "${YQ_SHA256}  yq" | sha256sum -c - \
 && install -m 0755 yq /usr/local/bin/yq \
 && curl -fsSLO "${gh}/oras-project/oras/releases/download/v${ORAS}/oras_${ORAS}_linux_amd64.tar.gz" \
 && echo "${ORAS_SHA256}  oras_${ORAS}_linux_amd64.tar.gz" | sha256sum -c - \
 && tar -xzf "oras_${ORAS}_linux_amd64.tar.gz" oras \
 && install -m 0755 oras /usr/local/bin/oras \
 && curl -fsSLO "${gh}/rhysd/actionlint/releases/download/v${ACTIONLINT}/actionlint_${ACTIONLINT}_linux_amd64.tar.gz" \
 && echo "${ACTIONLINT_SHA256}  actionlint_${ACTIONLINT}_linux_amd64.tar.gz" | sha256sum -c - \
 && tar -xzf "actionlint_${ACTIONLINT}_linux_amd64.tar.gz" actionlint \
 && install -m 0755 actionlint /usr/local/bin/actionlint \
 && curl -fsSL -o zizmor.tar.gz "${gh}/zizmorcore/zizmor/releases/download/v${ZIZMOR}/zizmor-x86_64-unknown-linux-gnu.tar.gz" \
 && echo "${ZIZMOR_SHA256}  zizmor.tar.gz" | sha256sum -c - \
 && tar -xzf zizmor.tar.gz zizmor \
 && install -m 0755 zizmor /usr/local/bin/zizmor \
 && curl -fsSL -o sops "${gh}/getsops/sops/releases/download/v${SOPS}/sops-v${SOPS}.linux.amd64" \
 && echo "${SOPS_SHA256}  sops" | sha256sum -c - \
 && install -m 0755 sops /usr/local/bin/sops \
 && cd / && rm -rf /tmp/seat
WORKDIR /

RUN morzer --version && yq --version && oras version && actionlint --version \
 && zizmor --version && sops --version && age --version && minisign -v \
 && shellcheck --version && zstd --version && docker compose version
