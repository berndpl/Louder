<img src="AppIconRounded.png" width="128" alt="Louder app icon">

# Louder

Drop a video on it. The voice gets loud and clear. That's it.

<img src="ScreenshotIdle.gif" width="460" alt="Louder's idle window: a leaf icon with arrows briefly sweeping inward toward it, the preset menu set to Louder, a 4K/1080p toggle, and the hint 'Drop videos here or on the Dock icon'">

Recordings from screencasts, demos, and meetings almost always have the same problem: the picture is fine, but the voice comes out quiet, thin, and buried under room noise. Louder is a single‑purpose macOS app that fixes exactly that. You launch it to the small window above, pick a preset once, and drag a file in — it raises your voice to a consistent, broadcast‑standard loudness, removes background noise, and trims the dead air, then writes the result back in place. No timeline, no plugins, nothing to configure.

<img src="Screenshot.png" width="460" alt="Louder showing loudness, isolation, and trim results after comparing presets on a clip">

## What it does

Drag one or more video or audio files onto the Dock icon (or the drop window). For each file, Louder:

1. Backs up the original to `<name> - original.<ext>` next to the file.
2. Probes the audio tracks with ffprobe.
3. Applies one remembered preset — **Louder**, **Studio**, **Focus**, or **Clean** (see [Presets](#presets) below).
4. Optionally chooses **Compare** as the final preset-menu item to leave the source untouched and create one clearly named variant for **every** preset (Louder, Studio, Focus, Clean) beside it.
5. By default, adds natural 0.25-second audio fades at the beginning and end. The persisted Settings toggle can turn this off; clips shorter than 0.5 seconds or without a reliable duration are normalized without fades.
6. Copies the video stream untouched and re-encodes audio as broadly-compatible **48 kHz AAC-LC**, writing the result with the `moov` atom up front (`+faststart`) so it begins playing immediately on web players, embedded viewers, and devices — then replaces the original file in place.

The window stays open after processing with compact measured loudness curves, integrated LUFS, estimated signal-to-noise ratio, and a native Undo action. Click any curve to hear that version; switching curves keeps the current timestamp for immediate A/B comparison. If a file fails, the original is left untouched.

## Presets

All presets target a consistent **−16 LUFS** loudness and differ only in how they clean the voice before the boost. **Compare** (the last menu item) runs all four at once, leaves the source untouched, and writes one clearly named variant beside it so you can A/B them.

| Preset | Signal path | Effect |
| --- | --- | --- |
| **Louder** | DeepFilterNet3 denoise → loudness boost | The safe default. Gentle stationary-noise cleanup, then brings the voice up to a consistent level. Closest to "just make it louder." |
| **Studio** | DeepFilterNet3 denoise → studio EQ + compression → boost | Adds a warm broadcast tone: high-pass rumble cut, low-end and presence shaping, and gentle compression for an even, "produced" sound. |
| **Focus** | Event-gate (Apple SoundAnalysis) → DeepFilterNet3 denoise → boost | Detects and ducks intermittent background events (a door, a dog, keyboard clatter) before denoising. Best when the room is occasionally noisy rather than constantly. |
| **Clean** | AI speech enhancement (neural model) → boost | Rebuilds the voice with an on-device neural model for the strongest cleanup of complex, non-stationary noise. Band-limited, so it sounds clearer but slightly duller than the 48 kHz presets — try it when the others leave too much noise. |

Each variant is saved as `<name> - <Preset>.<ext>` (e.g. `talk - Studio.mp4`).

The **ⓘ** button beside the preset menu opens a schematic "signal chain" — the stages of the selected preset drawn as connected stompboxes — with the exact model and parameters behind each stage (DeepFilterNet3, Apple SoundAnalysis, the neural enhancer, the EQ/compressor/loudness settings) and links to the relevant documentation. No secrets: it's there to show how the processing actually works.

## Output quality

A small **4K / 1080p** control on the drop screen sets a maximum output height (4K = 2160, 1080p = 1080). It works as a cap, not a forced size:

- A recording **at or below** the cap keeps its original video, copied untouched (the default, fastest path).
- A recording **above** the cap is downscaled to the cap and re-encoded to broadly-compatible **H.264 8-bit 4:2:0** (CRF 18, `veryfast`), preserving aspect ratio.

The choice is remembered between launches. Whenever the video is actually re-encoded — by a downscale, or by a silence trim — a **Size** assessment card appears showing the file-size change (e.g. `120 MB → 66 MB`). In a **Compare** batch the smallest re-encoded variant is starred. Files copied untouched and audio-only inputs show no Size card.

## Playback compatibility

Louder targets the widest possible device support: output audio is always 48 kHz AAC-LC and every file is written `+faststart`. Because the **video stream is copied untouched** (never re-encoded, to preserve quality and speed), the output's video compatibility matches your source recording. After each file is saved Louder inspects the result and surfaces a clear warning if it finds a limitation — for example an **H.265 (HEVC)** video copied from your recording (great on recent Apple gear, but not on many older phones, TVs, or browsers), a high-bit-depth/4:2:2 pixel format, or an audio/video length mismatch that could drift. For the broadest reach, record screencasts in **H.264**. (When Louder trims silence it does re-encode the trimmed video to H.264 8-bit 4:2:0.)

Louder also detects **multi-channel (surround) audio**. Mono and stereo are left untouched, but recordings with more than two channels (e.g. 5.1) are automatically merged down to a single mono channel to avoid silent or broken playback on devices that can't decode the surround layout — and Louder shows a short note when it does.

The Fades preference lives in **Louder → Settings**.

## Requirements

- macOS on **Apple Silicon** (the bundled DeepFilterNet denoiser is an `arm64` binary)
- ffmpeg via Homebrew:

  ```sh
  brew install ffmpeg
  ```

  Louder looks for `ffmpeg`/`ffprobe` in `/opt/homebrew/bin` (Apple Silicon) and `/usr/local/bin`. If they're missing it fails gracefully and tells you the command above.

DeepFilterNet 0.5.6 and the DeepFilterNet3 model are bundled (Apple Silicon). Cleanup runs completely locally and does not upload recordings.

## Building

Open `Louder.xcodeproj` in Xcode and run. There's nothing else to configure.

The app is deliberately **not sandboxed** — it needs to rewrite files in place anywhere on disk, including cloud-synced folders like OneDrive (which triggers a one-time macOS permission prompt on first use).

## Why an app and not a Shortcuts Quick Action?

A Quick Action was tried first and abandoned: Quick Actions run inside Apple's sandboxed `siriactionsd` daemon, which can never be granted access to OneDrive/CloudStorage files — the permission prompt simply can't be shown to a background daemon. A real app in the user session gets the prompt once and works forever.

## Non-goals

No editing, trimming, format conversion, folder watching, arbitrary audio parameters, or App Store distribution. It's a personal tool that does one thing.
