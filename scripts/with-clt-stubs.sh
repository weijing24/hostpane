#!/bin/sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$root/scripts/lib/clt-metal-stubs.sh"
hostpane_setup_clt_metal_stubs "$root"

if [ $# -eq 0 ]; then
  printf "export PATH=%s\n" "$PATH"
  exit 0
fi

exec "$@"
