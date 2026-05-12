# Cante

Cante is an early macOS lyrics overlay prototype.

## Current Prototype

The first milestone is intentionally small: a Swift CLI that reads text from standard input and renders the latest line in a translucent, borderless, click-through floating window.

Run it with:

```sh
swift run cante-overlay
```

Then type a line and press Return. Each new line replaces the overlay text.

Stop a running overlay from another terminal with:

```sh
.build/debug/cante-overlay --stop
```

`Ctrl-C` also works when the overlay is attached to your current terminal session.

You can also pipe timed text into it:

```sh
while true; do
  echo "Don't get any big ideas"
  sleep 2
  echo "They're not gonna happen"
  sleep 2
done | swift run cante-overlay
```

## Lyrics-Only Streaming

The second CLI fetches synced lyrics from LRCLIB and prints each line according to its LRC timestamp:

```sh
swift run cante-lyrics --track "Nude" --artist "Radiohead"
```

Pipe it into the overlay:

```sh
swift build
swift run cante-lyrics --track "Nude" --artist "Radiohead" | .build/debug/cante-overlay
```

This does not know Spotify playback position yet. It treats command start as song start, which is enough to validate timestamp parsing and overlay updates. For faster visual testing, skip directly to the first lyric:

```sh
swift run cante-lyrics --track "Nude" --artist "Radiohead" --skip-intro true | .build/debug/cante-overlay
```

If lyrics are visible in the terminal but not in the overlay, run the overlay with stdin logging:

```sh
swift run cante-lyrics --track "Nude" --artist "Radiohead" --skip-intro true | .build/debug/cante-overlay --debug-stdin
```

## Spotify Sync Prototype

`cante-spotify` reads the current Spotify desktop playback through macOS scripting, fetches synced lyrics from LRCLIB when the track changes, and prints the lyric line that matches Spotify's playback position.

```sh
swift build
.build/debug/cante-spotify | .build/debug/cante-overlay
```

For troubleshooting:

```sh
.build/debug/cante-spotify --debug | .build/debug/cante-overlay --debug-stdin
```

This prototype requires the Spotify desktop app to be running. macOS may ask for permission to let Cante control Spotify.

The overlay shows a loading state while lyrics are being fetched or Spotify is not actively playing. Once lyrics are available, it shows the current line and the next line underneath.

Fetched LRCLIB results are cached locally in the user cache directory, so repeated tracks avoid another network request.

Clear the lyrics cache with:

```sh
swift run cante-lyrics --clear-cache
```

## Manual Validation Checklist

- The overlay appears above normal app windows.
- The overlay remains visible when switching Spaces/desktops.
- The overlay does not capture mouse clicks.
- The background is translucent/blurred.
- New stdin lines update the displayed lyric.
- Timestamped LRCLIB lyrics stream into the overlay.
- Spotify desktop playback position drives the current lyric line.

## Next Small Steps

- Add flags for position, opacity, and click-through behavior.
- Add a local HTTP or WebSocket input bridge.
- Parse timestamped LRC lines and animate current/next lyric state.
