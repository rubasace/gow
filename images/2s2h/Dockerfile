ARG BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:edge

# renovate: datasource=github-releases depName=HarbourMasters/2ship2harkinian
ARG S2H_VERSION=4.0.2

############################################################
# Stage 1 - fetch + extract
############################################################
FROM ${BASE_APP_IMAGE} AS fetch
ARG S2H_VERSION
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /fetch
# The Linux asset is named "2Ship-<Codename>-Linux.zip" (the codename changes every
# release), so we resolve the real URL via the GitHub API from the tag.
# (Anonymous API: 60 req/h per IP; plenty for occasional builds.)
RUN set -eux; \
    url="$(curl -fsSL "https://api.github.com/repos/HarbourMasters/2ship2harkinian/releases/tags/${S2H_VERSION}" \
            | grep browser_download_url | grep -- '-Linux.zip' | head -1 | cut -d'"' -f4)"; \
    test -n "$url"; \
    echo "Asset: $url"; \
    curl -fsSL -o 2ship.zip "$url"; \
    unzip -q 2ship.zip; \
    chmod +x 2ship.appimage; \
    ./2ship.appimage --appimage-extract >/dev/null; \
    test -x squashfs-root/usr/bin/2s2h.elf

############################################################
# Stage 2 - runtime (ready for Wolf)
############################################################
FROM ${BASE_APP_IMAGE} AS runtime
ARG S2H_VERSION
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libglvnd0 libopengl0 libglx0 libgl1 libegl1 \
 && rm -rf /var/lib/apt/lists/*


COPY --from=fetch /fetch/squashfs-root /opt/2s2h
RUN chmod +x /opt/2s2h/usr/bin/2s2h.elf

# Baked-in version: 10-2s2h-config.sh compares it against the volume's marker to know
# whether a MAJOR bump (X.0.0) requires regenerating mm.o2r.
ENV S2H_VERSION=${S2H_VERSION}

# 2S2H's data home (config, Save/, logs, mods, extraction output). GetAppDirectoryPath()
# honours $SHIP_HOME on Linux; this is the per-user home Wolf mounts. Set here so it's part
# of the image env, inherited all the way down to 2s2h.elf.
ENV SHIP_HOME=/home/retro

# Default settings, seeded into the per-user home on first launch (see 10-2s2h-config.sh).
# /cfg is base-app's convention for baked default configs (it ships sway/waybar there too);
# COPY merges into it (never wipes existing files), exactly like es-de. Drop more files into
# configs/ and they all land in /cfg.
COPY configs/ /cfg/

# Init flow: entrypoint runs /etc/cont-init.d/* as ROOT (we add 40-2s2h-bundle-links.sh to
# bridge the shared mm.o2r into the root-owned bundle), then drops to 'retro' and runs
# startup-app.sh, which sources /opt/gow/startup.d/* (per-user setup: 10-2s2h-config.sh) and
# finally launcher /opt/2s2h/launch-2s2h.sh. Users can mount more into either dir.
COPY scripts/40-2s2h-bundle-links.sh /etc/cont-init.d/40-2s2h-bundle-links.sh
COPY scripts/2s2h-lib.sh             /opt/2s2h/2s2h-lib.sh
COPY scripts/startup-app.sh          /opt/gow/startup-app.sh
COPY scripts/10-2s2h-config.sh       /opt/gow/startup.d/10-2s2h-config.sh
COPY scripts/launch-2s2h.sh          /opt/2s2h/launch-2s2h.sh
RUN chmod +x /opt/gow/startup-app.sh /opt/2s2h/launch-2s2h.sh

ENV RUN_SWAY=1 \
    GOW_REQUIRED_DEVICES="/dev/input/* /dev/dri/* /dev/nvidia* /dev/uinput"
