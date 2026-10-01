# Changelog

All notable changes to this plugin are documented here. Versions follow
[Semantic Versioning](https://semver.org): breaking changes to the CLI,
config keys, or plugin id bump the major version; new features bump minor;
fixes bump patch. Add entries under **Unreleased**, then run
`scripts/release patch|minor|major`.

## Unreleased

## 0.3.0 — 2026-09-30

- The plugin runs its own Audiobookshelf 2.37.1 (`omarchy-audiobook-abs`) in
  the background. It runs as you with `--restart unless-stopped` and listens
  on localhost only.
- On first start the plugin creates the admin account (your username, a
  generated password), a library on `ABS_LIBRARY_DIR` (default
  `~/Audiobooks`) that is scanned right away, and its own API key. It saves
  them to `~/.config/omarchy-audiobook/abs.env`, so notification links go
  straight to the book with no setup step.
- New **Listen on your phone** section in the panel: shows the Tailscale
  Serve address when one fronts the server, with **Copy server** and
  **Copy password** buttons for signing in from Absorb.
- New `server` command: `info`, `up`, `down`, `password`, `copy-password`.
- `doctor --fix` and the widget bring the server up. A plugin release that
  moves the Audiobookshelf image recreates the container and keeps its data.
- **Breaking:** `ABS_CONTAINER` now defaults to `omarchy-audiobook-abs`, and
  `OUTPUT_DIR` defaults to the library. To keep using an Audiobookshelf you
  run yourself, set `ABS_MANAGED=false`.
- `setup` saves its key to `abs.env` instead of `config`.

## 0.2.0 — 2026-09-30

- **Breaking:** no longer uses an existing `ebook2audiobook` container. Each
  book runs in a throwaway `docker run --rm` container from the published
  image, pinned to ebook2audiobook v26.9.27.
- The image is pulled automatically on first use, with download progress in
  the panel. CUDA is chosen for NVIDIA drivers 580+, CPU otherwise.
- `omarchy-audiobook doctor [--fix]` checks for and installs Docker, the
  NVIDIA container toolkit and docker group membership. When something is
  missing, the panel shows a **fix** row and failed jobs link to it.
- Models are cached in `~/.local/share/omarchy-audiobook/models` (an
  existing `~/ebook2audiobook/models` is reused), and first-run model
  downloads show up as their own phases.
- Output files are owned by you, and ebook2audiobook's temp files are thrown
  away with the container.
- With Audiobookshelf down, books go to `~/Audiobooks/<Author>/<Title>/`.
- The widget registers the CLI and Open With handler itself, so
  `omarchy plugin add` installs need no extra step.
- New commands: `engine pull`, `version`.

## 0.1.0 — 2026-09-30

- Bar widget with progress, ETA, cancel, recent books, and a list of recent EPUBs.
- `omarchy-audiobook` CLI: convert EPUBs with ebook2audiobook on the GPU,
  one job at a time in transient systemd user units.
- Import finished M4Bs into Audiobookshelf as `<Author>/<Title>/`, rescan,
  and notify with a link to the item.
- "Convert to Audiobook" Open With handler for EPUBs.
