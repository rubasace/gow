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

# Baked-in version: 10-soh-config.sh compares it against the volume's marker to know
# whether a MAJOR bump (X.0.0) requires regenerating oot.o2r.
ENV SOH_VERSION=${SOH_VERSION}

# SoH's data home (config, Save/, logs, mods, extraction output). GetAppDirectoryPath()
# honours $SHIP_HOME on Linux; this is the per-user home Wolf mounts. Set here so it's part
# of the image env, inherited all the way down to soh.elf.
ENV SHIP_HOME=/home/retro

# Default settings, seeded into the per-user home on first launch (see 10-soh-config.sh).
# /cfg is base-app's convention for baked default configs (it ships sway/waybar there too);
# COPY merges into it (never wipes existing files), exactly like es-de. Drop more files into
# configs/ and they all land in /cfg.
COPY configs/ /cfg/

# gow contract: entrypoint -> startup.sh -> /opt/gow/startup-app.sh, which sources
# /opt/gow/startup.d/* (as 'retro') and then runs launcher /opt/soh/launch-soh.sh.
# Our per-user setup is the 10-soh-config.sh fragment; users can mount more into startup.d/.
COPY scripts/startup-app.sh   /opt/gow/startup-app.sh
COPY scripts/10-soh-config.sh /opt/gow/startup.d/10-soh-config.sh
COPY scripts/launch-soh.sh    /opt/soh/launch-soh.sh
RUN chmod +x /opt/gow/startup-app.sh /opt/soh/launch-soh.sh

ENV RUN_SWAY=1 \
    GOW_REQUIRED_DEVICES="/dev/input/* /dev/dri/* /dev/nvidia* dev/uinput"
