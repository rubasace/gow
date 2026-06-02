# Ship of Harkinian for Wolf (Games on Whales)

Wolf image that **packages the official Linux release** of Ship of Harkinian — the *Ocarina of Time*
PC port — with no compiling. State lives in three places:

- **the binary** is baked into the image, matched to the version;
- **settings and saves** stay **per-user** in the home Wolf auto-mounts;
- **the ROM** and the derived **`oot.o2r`** live in a **shared folder** you manage on the host.

Updating is just bumping the image tag and rebuilding — saves are untouched and the ROM isn't
re-extracted, except on a major version jump (handled automatically, see [Updating](#updating)).

## Where things live

| Lives in | What | Persistence |
| - | - | - |
| **Image** (`/opt/soh`, read-only) | `soh.elf` + libs + `soh.o2r` + `assets` | ships with the release |
| **Wolf home** (`/home/retro`, auto) | `shipofharkinian.json`, `Save/`, `mods/` | **per-user** (Wolf mounts it per profile) |
| **Shared** (`/mnt/wolf/shared/shipofharkinian` → `/roms`) | ROM `.z64`, common `oot.o2r`, `mods/` | **shared** across profiles, you manage it |

You only ever provide the **ROM `.z64`**. The `oot.o2r` is derived from it — either drop one in the
shared folder yourself (e.g. the one from your Windows setup) or let the container generate it on first
launch.

## Usage

1. **Build** on the Wolf host (so the image stays local — Wolf launches containers through the host's
   docker socket), from this folder:
   ```bash
   docker build -t soh:wolf .
   # pin a version: docker build --build-arg SOH_VERSION=9.2.3 -t soh:wolf .
   ```
2. **Shared folder + ROM** on the host:
   ```bash
   sudo mkdir -p /mnt/wolf/shared/shipofharkinian
   sudo cp "your-rom.z64" /mnt/wolf/shared/shipofharkinian/   # OoT NTSC 1.0 US recommended
   # optional: drop an already-generated oot.o2r here to skip generation entirely
   # to let the container generate + share the oot.o2r itself, make the folder writable:
   sudo chown 1000:1000 /mnt/wolf/shared/shipofharkinian
   ```
3. Paste `wolf/config.snippet.toml` into Wolf's `config.toml` and restart Wolf. It shows up in Moonlight.
4. **First connection:** if you didn't provide an `oot.o2r`, SoH extracts it from the ROM and shares it
   back. This is **hands-free** — you see a brief extraction screen and an automatic restart, no clicks
   (so a Moonlight gamepad user never gets stuck on a keyboard prompt). Settings and saves go to your
   per-user home.

## Updating

Bump the image tag and rebuild. Whether the ROM is re-extracted depends on the version jump:

- **`0.0.X` / `0.X.0`** (patch / feature) → the common `oot.o2r` is reused. Just rebuild and redeploy.
- **`X.0.0`** (major) → the `oot.o2r` may be outdated; the container detects it and **regenerates it
  automatically and hands-free** from the ROM, then shares the fresh one back. You still only provide
  the `.z64`. (Needs the shared folder writable; on a read-only mount it warns instead.)

The version pin (`ARG SOH_VERSION` in the Dockerfile) is kept up to date by Renovate — see
[CONTRIBUTING](../../CONTRIBUTING.md).

## Settings and mods

- **Settings:** the image ships a default `shipofharkinian.json` (fullscreen, match refresh rate,
  OpenGL, a pre-mapped controller), seeded into a profile **only on first launch**. After that the
  user's own changes persist per-profile.
- **Mods:** drop `.o2r` / `.otr` files in `/mnt/wolf/shared/shipofharkinian/mods/`; they're symlinked
  into each profile's `mods/` on launch (shared once, not duplicated per profile). To enable one by
  default its filename must match `gSettings.EnabledMods` in the JSON; disabling is a toggle in SoH's
  menu, saved per-profile.

## Notes

- **NVIDIA:** keep `/dev/nvidia*` in `GOW_REQUIRED_DEVICES` (already in the snippet); on Intel/AMD
  base-app's Mesa is enough.
- **Not tested end-to-end** (no Docker in the authoring environment): built against the official
  release, the `gow` base-app contract, and inspection of the AppImage.
- Implementation details (build stages, the hands-free extraction flow, how the `oot.o2r` is bridged in)
  live in the commented `Dockerfile` and `scripts/`.
