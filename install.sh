#!/bin/bash

# Install from a checkout: copy the plugin into Omarchy, put the CLI on PATH,
# register "Convert to Audiobook", then make sure Docker, GPU access and the
# ebook2audiobook image are ready so the first conversion starts right away.
#
# The plugin is copied rather than symlinked because the shell's inotify
# watcher doesn't follow symlinks, so re-running this is also how edits get
# hot-reloaded. (`omarchy plugin add <git-url>` works too: the widget does the
# PATH/Open With step itself, and the image downloads on first conversion.)

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd -P)
plugin_dir="$HOME/.config/omarchy/plugins/omarchy-audiobook"

[[ -L $plugin_dir ]] && rm -f "$plugin_dir"
mkdir -p "$plugin_dir"
rsync -a --delete --exclude .git --exclude install.sh --exclude scripts --exclude "screenshot*.png" "$here/" "$plugin_dir/"

"$plugin_dir/bin/omarchy-audiobook" _integrate
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
omarchy plugin enable omarchy-audiobook --section right >/dev/null 2>&1 || true

echo "Installed omarchy-audiobook $("$plugin_dir/bin/omarchy-audiobook" version)."
[[ ${1:-} == --no-deps ]] && exit 0
"$plugin_dir/bin/omarchy-audiobook" doctor --fix
