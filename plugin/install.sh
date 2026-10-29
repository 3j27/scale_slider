#!/usr/bin/env bash
# Install the Scale Slider bar widget into Omarchy's user plugin directory.
# Files are copied (not linked) — the omarchy shell hot-reloads anything under
# ~/.config/omarchy/plugins/, so re-running this script applies updates live.

set -euo pipefail

plugin_dir="${HOME}/.config/omarchy/plugins/admin.scale-slider"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The CLI must be on PATH for the omarchy shell to call it.
if ! command -v scale-slider >/dev/null 2>&1; then
  echo "scale-slider not found on PATH."
  if [[ -x "${repo_dir}/build/scale-slider" ]]; then
    mkdir -p "${HOME}/.local/bin"
    ln -sf "${repo_dir}/build/scale-slider" "${HOME}/.local/bin/scale-slider"
    echo "Linked ${repo_dir}/build/scale-slider -> ${HOME}/.local/bin/scale-slider"
  else
    echo "Build it first: ./bin/build" >&2
    exit 1
  fi
fi

mkdir -p "${plugin_dir}/i18n"
cp "${repo_dir}/plugin/manifest.json" "${plugin_dir}/manifest.json"
cp "${repo_dir}/plugin/Panel.qml" "${plugin_dir}/Panel.qml"
cp "${repo_dir}"/plugin/i18n/*.json "${plugin_dir}/i18n/"

echo "Installed to ${plugin_dir}"
cat <<'EOF'

Next step (one-time): add the widget to the bar in ~/.config/omarchy/shell.json —

  "right": [
    { "id": "admin.scale-slider" },   // e.g. beside omarchy.audio
    ...
  ]

The shell hot-reloads shell.json on save. Re-run this script to update the
plugin after editing plugin/ in the repo.
EOF
