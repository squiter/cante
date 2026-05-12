# Changelog

All notable changes to Cante will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses version tags such as `v0.1.0`.

## [Unreleased]

## [0.2.0] - 2026-05-12

### Added

- Overlay option for a dark text shadow that keeps lyrics readable over bright backgrounds (`--text-shadow` / `--no-text-shadow`).
- Overlay option for an opaque dark backdrop instead of the translucent material (`--opaque` / `--no-opaque`).
- Optional `~/.config/cante/config.json` file to set persistent overlay defaults; CLI flags override the file.

## [0.1.0] - 2026-05-12

### Added

- Floating translucent macOS overlay for desktop lyrics and teleprompter text.
- Top-level `cante` CLI with `run`, `stop`, and `clear-cache` commands.
- Spotify desktop sync using macOS scripting for current track, playback state, and playback position.
- LRCLIB synced lyrics lookup with local caching.
- Current lyric plus next lyric rendering.
- Loading state with animated dots and current track metadata.
- Missing-synced-lyrics state that fades the overlay until the next song.
- Overlay close button and draggable overlay window.
- Teleprompter usage via plain text or JSON Lines streamed to stdin.
- GitHub Actions release workflow that builds and packages macOS binaries.

### Changed

- README examples now use songs by The Warning.

### Notes

- Spotify queue prefetching is not implemented yet. It likely requires Spotify Web API OAuth and the playback scopes needed for the queue endpoint.
