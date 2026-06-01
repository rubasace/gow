#!/bin/bash
# Hook run by base-app (entrypoint -> startup.sh -> startup-app.sh), as user retro.
set -e

source /opt/gow/bash-lib/utils.sh
source /opt/gow/launch-comp.sh   # defines the launcher() function

gow_log "[SoH] Lanzando Ship of Harkinian"

# launcher brings up the compositor (sway/gamescope per RUN_SWAY/RUN_GAMESCOPE)
# and runs the command inside it. We pass our wrapper to pin the CWD.
launcher /opt/soh/launch-soh.sh
