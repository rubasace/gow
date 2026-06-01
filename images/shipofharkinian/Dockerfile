ARG BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:edge

# renovate: datasource=github-releases depName=HarbourMasters/Shipwright
ARG SOH_VERSION=9.2.3

############################################################
# Stage 1 - fetch + extract
############################################################
FROM ${BASE_APP_IMAGE} AS fetch
ARG SOH_VERSION
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /fetch
# The Linux asset is named "SoH-<Codename>-Linux.zip" (the codename changes every
# release), so we resolve the real URL via the GitHub API from the tag.
# (Anonymous API: 60 req/h per IP; plenty for occasional builds.)
RUN set -eux; \
    url="$(curl -fsSL "https://api.github.com/repos/HarbourMasters/Shipwright/releases/tags/${SOH_VERSION}" \
            | grep browser_download_url | grep -- '-Linux.zip' | head -1 | cut -d'"' -f4)"; \
    test -n "$url"; \
    echo "Asset: $url"; \
    curl -fsSL -o soh.zip "$url"; \
    unzip -q soh.zip; \
    chmod +x soh.appimage; \
    ./soh.appimage --appimage-extract >/dev/null; \
    test -x squashfs-root/usr/bin/soh.elf

############################################################
# Stage 2 - runtime (ready for Wolf)
############################################################
FROM ${BASE_APP_IMAGE} AS runtime
ARG SOH_VERSION
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libglvnd0 libopengl0 libglx0 libgl1 libegl1 \
 && rm -rf /var/lib/apt/lists/*


COPY --from=fetch /fetch/squashfs-root /opt/soh
RUN chmod +x /opt/soh/usr/bin/soh.elf

# Baked-in version: launch-soh.sh compares it against the volume's marker to know
# whether a MAJOR bump (X.0.0) requires regenerating oot.o2r.
ENV SOH_VERSION=${SOH_VERSION}

# gow contract: entrypoint -> startup.sh -> /opt/gow/startup-app.sh -> launcher <cmd>
COPY scripts/startup-app.sh /opt/gow/startup-app.sh
COPY scripts/launch-soh.sh  /opt/soh/launch-soh.sh
RUN chmod +x /opt/gow/startup-app.sh /opt/soh/launch-soh.sh

ENV RUN_SWAY=1 \
    GOW_REQUIRED_DEVICES="/dev/input/* /dev/dri/* /dev/nvidia* dev/uinput"
