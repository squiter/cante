# Cante

Cante shows the current Spotify lyric line in a floating macOS desktop overlay, with the next line underneath.

## Download

Cante ships as a macOS command-line bundle on GitHub Releases.

1. Open the [Releases page](https://github.com/squiter/cante/releases).
2. Download the latest `cante-...-macos-...tar.gz` archive.
3. Download the matching `.sha256` file if you want to verify the archive.
4. Unpack the archive.

```sh
tar -xzf cante-*-macos-*.tar.gz
cd cante-*-macos-*
```

Keep the included binaries together in the same folder:

```text
cante
cante-overlay
cante-spotify
cante-lyrics
```

## Allow Binaries On macOS

The release binaries are not notarized, so macOS Gatekeeper blocks them by default with a "cannot be opened because the developer cannot be verified" message. Remove the quarantine flag once after unpacking:

```sh
xattr -dr com.apple.quarantine cante cante-overlay cante-spotify cante-lyrics
```

Run this from inside the unpacked release folder. After that the binaries launch normally.

## Run Cante

Start Spotify, play a song, then run:

```sh
./cante run
```

The first time you run it, macOS may ask for permission to let Cante control Spotify. Allow it so Cante can read the current track and playback position.

The overlay can be dragged around the screen. Close it with the `x` button, or from a terminal:

```sh
./cante stop
```

Clear cached lyrics:

```sh
./cante clear-cache
```

Run with debug logs:

```sh
./cante run --debug
```

Run in click-through mode:

```sh
./cante run --click-through
```

In click-through mode, the overlay ignores mouse events, so the close button and dragging are disabled. Use `./cante stop` to close it.

## Behavior

- Shows the current lyric line and the next lyric line.
- Shows the current track while lyrics are loading.
- Fades down when synced lyrics are not available for a song.
- Caches LRCLIB synced lyrics locally so repeated songs load faster.
- Floats above other windows and joins all Spaces.

## Build From Source

For development:

```sh
swift build
.build/debug/cante run
```

Create a GitHub release by pushing a version tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions will build release binaries, create a `.tar.gz` archive plus a SHA-256 checksum, and attach both files to the GitHub Release.

Release changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## Advanced Usage

The overlay reads from standard input, so you can drive it with your own scripts.

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

`cante-lyrics` fetches synced lyrics from LRCLIB and prints each line according to its LRC timestamp:

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

## Spotify Sync

`cante-spotify` reads the current Spotify desktop playback through macOS scripting, fetches synced lyrics from LRCLIB when the track changes, and prints the lyric line that matches Spotify's playback position.

```sh
swift build
.build/debug/cante-spotify | .build/debug/cante-overlay
```

For troubleshooting:

```sh
.build/debug/cante-spotify --debug | .build/debug/cante-overlay --debug-stdin
```

This requires the Spotify desktop app to be running. macOS may ask for permission to let Cante control Spotify.

The overlay shows a loading state while lyrics are being fetched or Spotify is not actively playing. Once lyrics are available, it shows the current line and the next line underneath.

Fetched LRCLIB results are cached locally in the user cache directory, so repeated tracks avoid another network request.

Clear the lyrics cache with:

```sh
.build/debug/cante clear-cache
```
