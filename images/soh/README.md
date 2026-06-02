# Ship of Harkinian for Wolf (Games on Whales)

Wolf image that **packages the official Linux release** of SoH (no compiling). It splits
state across three places: the binary is baked into the image, **settings and saves** stay
**per-user** in the home Wolf auto-mounts, and the **ROM** plus the **common `oot.o2r`** you
provide in a **shared folder** on the host. Updating SoH means bumping the image tag and
rebuilding — without touching saves or re-extracting, except on major version jumps.

## Layout

```
images/shipofharkinian/
├── Dockerfile              # fetch (download+extract the AppImage) · runtime (base-app)
├── .dockerignore
├── README.md
├── configs/                # COPY'd wholesale to /cfg (merges, es-de style)
│   └── shipofharkinian.json # default settings, seeded into the per-user home on first run
├── scripts/                # scripts COPIED into the image
│   ├── 40-soh-bundle-links.sh #  -> /etc/cont-init.d/ : ROOT, bridges oot.o2r into the bundle
│   ├── startup-app.sh       #   gow hook -> sources startup.d/*, then launcher
│   ├── 10-soh-config.sh     #   -> /opt/gow/startup.d/ : per-user prep (sourced as 'retro')
│   └── launch-soh.sh        #   -> /opt/soh/ : thin exec wrapper (run by launcher)
└── wolf/
    └── config.snippet.toml  # [[apps]] block for Wolf's config.toml
```

The **build context is this folder** (`images/shipofharkinian/`): the Dockerfile does
`COPY scripts/...` and `COPY configs/ /cfg/`. The ROM never enters the build.

## How it works

**Build (Dockerfile, 2 stages):**
1. **fetch** (`FROM base-app`): resolves the `SoH-<Codename>-Linux.zip` asset via the GitHub
   API from the `SOH_VERSION` tag (the codename changes every release), downloads it and
   extracts the AppImage with `--appimage-extract` (no FUSE).
2. **runtime** (`FROM base-app`): copies the extracted tree to `/opt/soh` (binary at
   `usr/bin/soh.elf`, with `rpath $ORIGIN/../lib` → its libs in `usr/lib`; plus `soh.o2r`,
   `assets/` and `gamecontrollerdb.txt`) and installs the GLVND layers (`libglvnd0`,
   `libopengl0`, `libglx0`, `libgl1`, `libegl1`). The real GPU driver comes from base-app/host.

**Runtime.** `base-app`'s entrypoint runs `/etc/cont-init.d/*` as **root**, then drops to
**`retro`** and runs our `startup-app.sh`, which sources `/opt/gow/startup.d/*` (as `retro`,
kodi-style — mount your own fragments there) and finally `launcher /opt/soh/launch-soh.sh`.

- **`/etc/cont-init.d/40-soh-bundle-links.sh`** (ROOT) bridges `oot.o2r`/`oot-mq.o2r` **into the
  image bundle** (`/opt/soh/usr/bin/oot.o2r → /roms/oot.o2r`). Root, because `/opt/soh` is
  root-owned and `retro` can't write there. SoH finds it via `LocateFileAcrossAppDirs` (bundle
  step) — so **no o2r symlink ends up in the home**. `soh.o2r`/`assets` come from the bundle too.

Our per-user setup lives in the **`/opt/gow/startup.d/10-soh-config.sh`** fragment (runs as
`retro`, never root, so everything it writes to the home is correctly owned):
1. `SHIP_HOME` is the **per-user home** (`/home/retro`, set as an image ENV; Wolf persists it
   per profile). SoH writes config, saves, logs, mods and the extraction output there — and
   **only** those (no archive symlinks; the home stays clean).
2. Symlinks the provided **mods** from `/roms/mods`, and locates the ROM (passed by path for
   extraction). The `oot.o2r` bridge is the cont-init one above.
3. Decides about `oot.o2r` (a DERIVED artifact — you only ever provide the `.z64`):
   - **a common one exists and matches** → uses it (via the cont-init bundle bridge).
   - **a common one exists but is from an older MAJOR** (marker) → **deletes it and regenerates**
     from the ROM, then promotes the fresh one back. (Needs the shared folder writable; on a
     read-only mount it warns instead.)
   - **none but a ROM is present** → it's generated (see below) and **promoted** to the shared
     folder (atomically, so concurrent sessions never corrupt it).
   - **neither** → clear error in the log.
4. **Hands-free extraction (no keyboard).** SoH's extractor parks on a "Run SoH?" confirm popup
   that appears *before* the controller is initialized — so a Moonlight gamepad user can't dismiss
   it. `launch-soh.sh` works around it: when there's no `oot.o2r`, it runs the extraction **in the
   background**, waits until the archive is fully written (its size stops growing), **kills** that
   instance (popup and all), and **relaunches clean** → the `oot.o2r` now exists, so SoH starts with
   **zero prompts**. You see a brief extraction screen + a quick restart, no clicks. This also covers
   MAJOR-version regenerations. With `oot.o2r` already present, it just launches — zero prompts.

> For zero interaction from day one, **provide the `oot.o2r` yourself** in the shared folder
> (e.g. the one from your Windows setup). Letting the container generate it costs **one click, once**.

## Data model

| Lives in | What | Persistence |
| - | - | - |
| **Image** (`/opt/soh`, RO) | `soh.elf` + libs + `soh.o2r` + `assets` | ships with the release, matched to the version |
| **Wolf home** (`/home/retro`, auto) | `shipofharkinian.json`, `Save/`, `mods/` | **per-user** (Wolf mounts it per profile) |
| **Shared** (`/mnt/wolf/shared/shipofharkinian` → `/roms`) | ROM `.z64`, common `oot.o2r`, `mods/` | **shared** across profiles, you manage it |

## Default settings and mods

- **Settings:** the image bakes `configs/` into `/cfg/` (so `/cfg/shipofharkinian.json`)
  (base-app's convention for default configs). `10-soh-config.sh` copies it into the home **only if the
  profile has none yet** → a default on first launch; after that the user's changes persist (per-profile).
  It ships fullscreen, `MatchRefreshRate`, OpenGL and a pre-mapped controller (`ControlNav`).
- **Mods:** drop the `.o2r`/`.otr` files in `/mnt/wolf/shared/shipofharkinian/mods/`. On each launch they
  are **symlinked** into `$HOME/mods` (not copied: avoids duplicating big packs per profile; not hardlinked
  either, since that can't cross mounts). To enable one by default, its filename must match
  `gSettings.EnabledMods` in the JSON. **Disabling** is a toggle in SoH's menu, saved to the profile's
  `shipofharkinian.json` (persists); the symlink stays but isn't applied.

## Usage

1. **Build** (on the Wolf host, so the image stays local), from this folder:
   ```bash
   docker build -t soh:wolf .
   # specific version: docker build --build-arg SOH_VERSION=9.2.3 -t soh:wolf .
   ```
2. **Shared folder + ROM** on the host:
   ```bash
   sudo mkdir -p /mnt/wolf/shared/shipofharkinian
   sudo cp "your-rom.z64" /mnt/wolf/shared/shipofharkinian/   # OoT NTSC 1.0 US recommended
   # optional: drop an already-generated oot.o2r there (e.g. the one from your Windows setup)
   # if you want the container to generate and share the oot.o2r itself, make it writable:
   sudo chown 1000:1000 /mnt/wolf/shared/shipofharkinian
   ```
3. Paste `wolf/config.snippet.toml` into Wolf's `config.toml` and restart it. It shows up in Moonlight.
4. **First connection:** if you didn't provide an `oot.o2r`, SoH extracts it from the ROM
   (`Processing OTR`) and it's promoted to the shared folder. Settings/saves go to your per-user home.

## Updating SoH

The version number tells you whether a re-extraction is needed:
- `0.0.X` (bugfix) and `0.X.0` (features) → **reuse** the common `oot.o2r`. Just rebuild + redeploy.
- `X.0.0` (major) → the common `oot.o2r` is outdated. `10-soh-config.sh` detects it via the marker and
  **regenerates it automatically and hands-free**: it deletes the stale `oot.o2r`, SoH rebuilds it
  from the ROM via the background-extract/relaunch flow (no keyboard, see above), and the fresh one is
  promoted back. You only ever provide the `.z64`. (Requires the shared folder writable; read-only → warns.)

**Renovate** keeps the pin: the Dockerfile's `ARG SOH_VERSION` is annotated with
`# renovate: datasource=github-releases depName=HarbourMasters/Shipwright`, and a `customManager` in the
repo-root `renovate.json5` picks it up.

## Notes

- **No Docker in this environment** → not tested end-to-end. Built on the official release, the real
  `gow` contract, and inspection of the 9.2.3 AppImage itself.
- **NVIDIA:** add `/dev/nvidia*` to `GOW_REQUIRED_DEVICES`; on Intel/AMD base-app's Mesa is enough.
- **`--appimage-extract` at build time:** does not need FUSE (it's the extract-without-mounting path).
  If your host refuses it, install `squashfs-tools` and extract the squashfs by offset.
- **If SDL can't find a backend** (audio/x11/wayland are dlopen'd at runtime): install it in the runtime
  stage. Inspect with: `docker run --rm -it --entrypoint bash soh:wolf -c 'ldd /opt/soh/usr/bin/soh.elf'`.
