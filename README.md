# Cante

Cante is an early macOS lyrics overlay prototype.

## Current Prototype

The first milestone is intentionally small: a Swift CLI that reads text from standard input and renders the latest line in a translucent, borderless, click-through floating window.

Run it with:

```sh
swift run cante-overlay
```

Then type a line and press Return. Each new line replaces the overlay text.

You can also pipe timed text into it:

```sh
while true; do
  echo "Don't get any big ideas"
  sleep 2
  echo "They're not gonna happen"
  sleep 2
done | swift run cante-overlay
```

## Manual Validation Checklist

- The overlay appears above normal app windows.
- The overlay remains visible when switching Spaces/desktops.
- The overlay does not capture mouse clicks.
- The background is translucent/blurred.
- New stdin lines update the displayed lyric.

## Next Small Steps

- Add flags for position, opacity, and click-through behavior.
- Add a local HTTP or WebSocket input bridge.
- Parse timestamped LRC lines and animate current/next lyric state.
