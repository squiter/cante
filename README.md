# Cante

Cante is an early macOS lyrics overlay prototype.

## Quick Start

```sh
swift build
.build/debug/cante run
```

Stop the overlay with the `x` button in the overlay UI, or from a terminal:

```sh
.build/debug/cante stop
```

Clear cached lyrics:

```sh
.build/debug/cante clear-cache
```

## GitHub Releases

Cante ships as a macOS command-line bundle on GitHub Releases. Download the `cante-...-macos-...tar.gz` archive, unpack it, and keep the included binaries together in the same folder:

```sh
tar -xzf cante-*-macos-*.tar.gz
cd cante-*-macos-*
./cante run
```

Create a release by pushing a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions will build the release binaries, create a `.tar.gz` archive plus a SHA-256 checksum, and attach both files to the GitHub Release.

## Current Prototype

The first milestone is intentionally small: a Swift CLI that reads text from standard input and renders the latest line in a translucent, borderless floating window.

Run it with:

```sh
swift run cante-overlay
```

Then type a line and press Return. Each new line replaces the overlay text.

Stop a running overlay from another terminal with:

```sh
.build/debug/cante stop
```

`Ctrl-C` also works when the overlay is attached to your current terminal session.

You can also pipe timed text into it:

```sh
while true; do
  echo "You want people to love you"
  sleep 2
  echo "It's encoded in your greed"
  sleep 2
done | swift run cante-overlay
```

## Teleprompter Mode

Cante can also work as a lightweight teleprompter because the overlay reads from standard input. The simplest format is one prompt line per line:

```text
Welcome everyone, and thanks for joining.
Today I want to show what Cante can do.
Let's start with the live desktop overlay.
```

Save that as `prompt.txt`, then stream it at your own pace:

```sh
while IFS= read -r line; do
  echo "$line"
  sleep 4
done < prompt.txt | .build/debug/cante-overlay
```

If you want the smaller second line to show what comes next, use JSON Lines. Each line should be one JSON object:

```jsonl
{"current":"Welcome everyone, and thanks for joining.","next":"Today I want to show what Cante can do."}
{"current":"Today I want to show what Cante can do.","next":"Let's start with the live desktop overlay."}
{"current":"Let's start with the live desktop overlay.","next":null}
```

Then stream the file the same way:

```sh
while IFS= read -r line; do
  echo "$line"
  sleep 4
done < prompt.jsonl | .build/debug/cante-overlay
```

Plain text updates only the main line. JSON Lines can update both the main line and the smaller next line.

## Lyrics-Only Streaming

The second CLI fetches synced lyrics from LRCLIB and prints each line according to its LRC timestamp:

```sh
swift run cante-lyrics --track "ERROR" --artist "The Warning"
```

Pipe it into the overlay:

```sh
swift build
swift run cante-lyrics --track "ERROR" --artist "The Warning" | .build/debug/cante-overlay
```

This does not know Spotify playback position yet. It treats command start as song start, which is enough to validate timestamp parsing and overlay updates. For faster visual testing, skip directly to the first lyric:

```sh
swift run cante-lyrics --track "ERROR" --artist "The Warning" --skip-intro true | .build/debug/cante-overlay
```

If lyrics are visible in the terminal but not in the overlay, run the overlay with stdin logging:

```sh
swift run cante-lyrics --track "ERROR" --artist "The Warning" --skip-intro true | .build/debug/cante-overlay --debug-stdin
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
.build/debug/cante clear-cache
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
