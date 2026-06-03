ARG BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:edge

# renovate: datasource=github-releases depName=HarbourMasters/Ghostship
ARG GHOSTSHIP_VERSION=2.0.0

############################################################
# Stage 1 - fetch + extract the official Linux AppImage
############################################################
FROM ${BASE_APP_IMAGE} AS fetch
ARG GHOSTSHIP_VERSION
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /fetch
# The Linux asset is named "<Codename>-Linux.zip" and the codename changes every release (2.0.0
# is "Mary-Celeste-Alfa-Linux.zip"; 1.0.x was "Ghostship-Dutchman-*-Linux.zip"), so we resolve
# the real URL via the GitHub API from the tag. (Anonymous API: 60 req/h per IP; plenty for
# occasional builds.) gamecontrollerdb.txt ships NEXT TO the appimage (not inside it). This
# libultraship doesn't auto-load it (SDL's built-in DB already covers the Moonlight virtual pad),
# but we fold it into the bundle and point SDL2 at it via SDL_GAMECONTROLLERCONFIG_FILE (runtime
# ENV) so a less common / passed-through controller is recognized too.
RUN set -eux; \
    url="$(curl -fsSL "https://api.github.com/repos/HarbourMasters/Ghostship/releases/tags/${GHOSTSHIP_VERSION}" \
            | grep browser_download_url | grep -- '-Linux.zip' | head -1 | cut -d'"' -f4)"; \
    test -n "$url"; \
    echo "Asset: $url"; \
    curl -fsSL -o ghostship.zip "$url"; \
    unzip -q ghostship.zip; \
    appimage="$(find . -maxdepth 1 -iname '*.appimage' | head -1)"; \
    test -n "$appimage"; \
    chmod +x "$appimage"; \
    "$appimage" --appimage-extract >/dev/null; \
    test -x squashfs-root/usr/bin/Ghostship; \
    if [ -f gamecontrollerdb.txt ]; then cp gamecontrollerdb.txt squashfs-root/usr/bin/gamecontrollerdb.txt; fi

############################################################
# Stage 2 - build the Torch asset extractor CLI
#
# Ghostship has no headless ROM->sm64.o2r path on Linux (the in-app extractor is a blocking GUI
# popup + file picker a Moonlight gamepad can't drive) and the release ships no extractor binary
# (Torch is compiled into the game, not shipped as a CLI). So we build Torch ourselves — at the
# EXACT commit Ghostship pins as its submodule for THIS version — and run it headlessly at first
# launch. Resolving the commit from the pin (rather than hardcoding) keeps the extractor in lock-
# step with the config.yml / asset YAMLs shipped in the image, so there's no schema drift.
############################################################
FROM ${BASE_APP_IMAGE} AS torch
ARG GHOSTSHIP_VERSION
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git ca-certificates jq \
      libbz2-dev zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
# Resolve Ghostship's pinned Torch submodule SHA for this tag, then build the standalone `torch`
# CLI exactly as Torch's own Linux CI does (USE_STANDALONE=ON, the linux-gnu toolchain). Torch
# pulls its remaining deps via CMake FetchContent at configure time (needs network, which the
# build has).
RUN set -eux; \
    torch_sha="$(curl -fsSL "https://api.github.com/repos/HarbourMasters/Ghostship/git/trees/${GHOSTSHIP_VERSION}" \
                  | jq -r '.tree[] | select(.path=="Torch") | .sha')"; \
    test -n "$torch_sha"; test "$torch_sha" != null; \
    echo "Torch commit: $torch_sha"; \
    git clone https://github.com/HarbourMasters/Torch.git; \
    cd Torch; \
    git checkout "$torch_sha"; \
    cmake -H. -Bbuild-cmake -GNinja \
      -DCMAKE_BUILD_TYPE=Release -DUSE_STANDALONE=ON \
      -DCMAKE_TOOLCHAIN_FILE=cmake/toolchain/linux-gnu.cmake; \
    cmake --build build-cmake -j"$(nproc)"; \
    test -x build-cmake/torch

############################################################
# Stage 3 - runtime (ready for Wolf)
############################################################
FROM ${BASE_APP_IMAGE} AS runtime
ARG GHOSTSHIP_VERSION
ENV DEBIAN_FRONTEND=noninteractive

# GL stack for the game; libbz2 + a current libstdc++6 for our self-built `torch` (compiled in
# the torch stage against that stage's libstdc++ — pull the same here so its ABI symbols resolve).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libglvnd0 libopengl0 libglx0 libgl1 libegl1 libbz2-1.0 libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /fetch/squashfs-root /opt/ghostship
COPY --from=torch /build/Torch/build-cmake/torch /opt/ghostship/torch
RUN chmod +x /opt/ghostship/usr/bin/Ghostship /opt/ghostship/torch

# Baked-in version: 10-ghostship-config.sh compares it against the volume's marker to know
# whether a MAJOR bump (X.0.0) requires regenerating sm64.o2r.
ENV GHOSTSHIP_VERSION=${GHOSTSHIP_VERSION}

# Ghostship's data home (config, saves, logs, mods, extraction output). libultraship's
# GetAppDirectoryPath() honours $SHIP_HOME on Linux; this is the per-user home Wolf mounts. Set
# here so it's part of the image env, inherited all the way down to the Ghostship binary.
ENV SHIP_HOME=/home/retro

# SDL2 (the game's bundled libSDL2) loads this mapping DB itself, independent of the app, so a
# controller SDL's built-in table doesn't know still gets recognized. The Moonlight virtual pad
# works without it; this just widens compatibility for a less common / passed-through controller.
ENV SDL_GAMECONTROLLERCONFIG_FILE=/opt/ghostship/usr/bin/gamecontrollerdb.txt

# Default settings, seeded into the per-user home on first launch (see 10-ghostship-config.sh).
# /cfg is base-app's convention for baked default configs; COPY merges into it (never wipes
# existing files). Drop more files into configs/ and they all land in /cfg.
COPY configs/ /cfg/

# Init flow: entrypoint runs /etc/cont-init.d/* as ROOT (we add 40-ghostship-bundle-links.sh to
# bridge the shared sm64.o2r into the root-owned bundle), then drops to 'retro' and runs
# startup-app.sh, which sources /opt/gow/startup.d/* (per-user setup: 10-ghostship-config.sh) and
# finally launcher /opt/ghostship/launch-ghostship.sh. Users can mount more into either dir.
COPY scripts/40-ghostship-bundle-links.sh /etc/cont-init.d/40-ghostship-bundle-links.sh
COPY scripts/ghostship-lib.sh             /opt/ghostship/ghostship-lib.sh
COPY scripts/startup-app.sh               /opt/gow/startup-app.sh
COPY scripts/10-ghostship-config.sh       /opt/gow/startup.d/10-ghostship-config.sh
COPY scripts/launch-ghostship.sh          /opt/ghostship/launch-ghostship.sh
RUN chmod +x /opt/gow/startup-app.sh /opt/ghostship/launch-ghostship.sh

ENV RUN_SWAY=1 \
    GOW_REQUIRED_DEVICES="/dev/input/* /dev/dri/* /dev/nvidia* /dev/uinput"
