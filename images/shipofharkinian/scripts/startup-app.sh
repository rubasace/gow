#!/bin/bash
# Hook run by base-app (entrypoint -> startup.sh -> startup-app.sh), as user 'retro'.
# Everything here runs UNPRIVILEGED, not root. Root-only setup belongs in /etc/cont-init.d/
# (run by base-app's entrypoint before it drops to 'retro').
set -e

source /opt/gow/bash-lib/utils.sh
source /opt/gow/launch-comp.sh   # defines the launcher() function

# Extra startup fragments, sourced as 'retro' just before launch (kodi-style extension
# point). Anyone using the image can mount their own scripts into /opt/gow/startup.d/.
for fragment in /opt/gow/startup.d/*; do
  if [ -f "$fragment" ]; then
    gow_log "[SoH] startup.d: sourcing $fragment"
    source "$fragment"
  fi
done

gow_log "[SoH] Launching Ship of Harkinian"

# launcher brings up the compositor (sway/gamescope per RUN_SWAY/RUN_GAMESCOPE) and runs
# the command inside it. Our wrapper does the per-user prep (also as 'retro').
launcher /opt/soh/launch-soh.sh
