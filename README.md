# LaPlayer

A minimal macOS video player built for one job: **stepping through video frame by frame and taking snapshots**.

Native Swift + AppKit + AVFoundation. No dependencies, no Xcode project — one shell script builds a standalone `.app`.

## Hotkeys

| Key | Action |
|---|---|
| `space` | Play / pause (replays when at the end) |
| `←` | Back 3 seconds |
| `→` | Forward 3 seconds |
| `,` (`<`) | Previous frame |
| `.` (`>`) | Next frame |
| `/` (`?`) | Snapshot — saves `{video_name}{i}.jpg` next to the video file |
| `⌘O` | Open a video |
| `⌃W` / `⌘Q` | Quit |

You can also drag a video file onto the window, click/drag the progress bar to seek, and the app reopens the last played video on launch.

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
  PlayerView.swift      Player, hotkeys, snapshot logic, overlay UI
  ProgressBarView.swift Seekable progress bar
Info.plist              Bundle metadata
icon.jpg                App icon source (1024×1024+ square JPEG)
build.sh                Build script → build/LaPlayer.app
```

## Notes

- Snapshots are taken at the exact current frame (zero-tolerance image generation) and saved as JPEG (quality 0.9). Filenames auto-increment and never overwrite existing files.
- Timestamps beside the progress bar are `H:MM:SS.FF`, where `FF` is the frame number within the current second, based on the video track's native frame rate.
- The app is ad-hoc signed, so it runs locally but will trigger Gatekeeper if distributed to other machines.
