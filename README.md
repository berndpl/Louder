<img src="AppIcon.png" width="128" alt="Louder app icon">

# Louder

Drop a video on it. The video gets loud. That's it.

A tiny macOS app that fixes quiet screen recordings and meeting captures (CleanShot, Teams, …) in place — no editor or fiddly audio controls.

## What it does

Drag one or more video or audio files onto the Dock icon (or the drop window). For each file, Louder:

1. Backs up the original to `<name> - original.<ext>` next to the file.
2. Probes the audio tracks with ffprobe.
3. Applies one remembered preset: **Boost** (`-14 LUFS`), **Boost + Denoise** (`-14 LUFS` plus DeepFilterNet), or **Gentle Boost + Denoise** (`-16 LUFS` plus DeepFilterNet).
4. Optionally chooses **Compare** as the final preset-menu item to leave the source untouched and create all three clearly named variants beside it.
5. By default, adds natural 0.25-second audio fades at the beginning and end. The persisted Settings toggle can turn this off; clips shorter than 0.5 seconds or without a reliable duration are normalized without fades.
6. Copies the video stream untouched, re-encodes audio as AAC, and replaces the original file in place.

The window stays open after processing with compact measured loudness curves, integrated LUFS, estimated signal-to-noise ratio, and a native Undo action. Click any curve to hear that version; switching curves keeps the current timestamp for immediate A/B comparison. If a file fails, the original is left untouched.

The Fades preference lives in **Louder → Settings**.

## Requirements

- macOS
- ffmpeg via Homebrew:

  ```sh
  brew install ffmpeg
  ```

  Louder looks for `ffmpeg`/`ffprobe` in `/opt/homebrew/bin` (Apple Silicon) and `/usr/local/bin` (Intel). If they're missing it fails gracefully and tells you the command above.

DeepFilterNet 0.5.6 and the DeepFilterNet3 model are bundled for Apple Silicon and Intel Macs. Cleanup runs completely locally and does not upload recordings.

## Building

Open `Louder.xcodeproj` in Xcode and run. There's nothing else to configure.

The app is deliberately **not sandboxed** — it needs to rewrite files in place anywhere on disk, including cloud-synced folders like OneDrive (which triggers a one-time macOS permission prompt on first use).

## Why an app and not a Shortcuts Quick Action?

A Quick Action was tried first and abandoned: Quick Actions run inside Apple's sandboxed `siriactionsd` daemon, which can never be granted access to OneDrive/CloudStorage files — the permission prompt simply can't be shown to a background daemon. A real app in the user session gets the prompt once and works forever.

## Non-goals

No editing, trimming, format conversion, folder watching, arbitrary audio parameters, or App Store distribution. It's a personal tool that does one thing.
