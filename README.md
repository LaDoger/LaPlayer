# LaPlayer

A minimal macOS video/audio player built for one job: **stepping through media frame by frame, taking snapshots, and trimming clips**.

Native Swift + AppKit + AVFoundation. No dependencies, no Xcode project — one shell script builds a standalone `.app`.

## Hotkeys

| Key | Action |
|---|---|
| `space` | Play / pause (replays when at the end) |
| `←` | Back 3 seconds |
| `→` | Forward 3 seconds |
| `↑` | Volume +5 (starts at 100) |
| `↓` | Volume -5 |
| `,` (`<`) | Previous frame (video) / back 1/24s (audio) |
| `.` (`>`) | Next frame (video) / forward 1/24s (audio) |
| `/` (`?`) | Snapshot — saves `{video_name}{i}.jpg` next to the video file (video only) |
| `i` | Mark trim start at the current position |
| `o` | Mark trim end at the current position |
| `⌘O` | Open a file |
| `⌃W` / `⌘Q` | Quit |

Once both a trim start and end are marked, the selected range is exported as `{name}_{i}.{ext}` next to the source file. Marking a start after the current end (or an end before the current start) clears the conflicting mark and keeps only the new one. Clicking or dragging on the progress bar snaps to a nearby trim marker.

Audio files (no video track) show the embedded cover art centered, falling back to a plain icon plus title/artist if there's none; snapshots aren't available since there's no frame to capture.

You can also drag a file onto the window, click/drag the progress bar to seek, and the app reopens the last played file on launch.

## Building

Requires macOS command-line tools (`xcode-select --install`).

```sh
./build.sh
open build/LaPlayer.app
```

The build script compiles `Sources/*.swift` with `swiftc`, assembles the `.app` bundle, converts `icon.jpg` into the app icon, and ad-hoc code-signs it.

## Project layout

```
Sources/
  main.swift            App entry point
  AppDelegate.swift     Window, menu, file-open handling
  PlayerView.swift      Player, hotkeys, snapshot/trim logic, overlay UI
  ProgressBarView.swift Seekable progress bar with trim markers and snapping
  MP3Trimmer.swift      Frame-accurate, lossless MP3 byte-slicing (no encoder needed)
Info.plist              Bundle metadata
icon.jpg                App icon source (1024×1024+ square JPEG)
build.sh                Build script → build/LaPlayer.app
```

## Notes

- Snapshots are taken at the exact current frame (zero-tolerance image generation) and saved as JPEG (quality 0.9). Filenames auto-increment and never overwrite existing files.
- Timestamps beside the progress bar are `H:MM:SS.FF`, where `FF` is the frame number within the current second, based on the video track's native frame rate.
- Video/most audio clip export uses `AVAssetExportSession` passthrough (no re-encode), so it is fast and lossless but cuts snap to the nearest keyframe at or before the marked start — the actual start may land slightly earlier than the exact frame chosen.
- MP3 is handled differently: `AVFoundation` can decode MP3 for playback but has no MP3 encoder, so `AVAssetExportSession` cannot write `.mp3` at all — not even passthrough. `MP3Trimmer.swift` works around this by parsing raw MPEG frame headers and slicing the compressed byte stream directly at frame boundaries (~26ms granularity), which is lossless and needs no encoder.
- The app is ad-hoc signed, so it runs locally but will trigger Gatekeeper if distributed to other machines.
