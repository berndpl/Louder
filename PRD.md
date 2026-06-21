# Louder

Drop a video on it. The video gets loud. That's it.

## Problem

Screen recordings and meeting captures (CleanShot, Teams, etc.) are often far too
quiet, and some have multiple audio tracks (mic + system audio) that players handle
inconsistently. Fixing this manually with ffmpeg works but is tedious.

A Shortcuts Quick Action was tried first and abandoned: Quick Actions execute inside
Apple's sandboxed `siriactionsd` daemon, which can never be granted access to
OneDrive/CloudStorage files (the "access data from OneDrive" permission prompt cannot
be shown to a background daemon). A real app in the user session gets the prompt
once and works forever — that's why Louder is an app.

## User

Just Bernd. Files frequently live in `~/Library/CloudStorage/OneDrive-Microsoft/`.

## Interaction model

- **Dock icon is the primary interface.** Drag video file(s) onto it; conversion
  happens in place with no required interaction ("headless").
- A small window opens automatically showing per-file progress — nice to see, never
  needed. It is also a drop target itself.
- Clicking the Dock icon opens the same drop window.

## Core flow (per file)

1. Back up the original to `<name> - original.<ext>` next to the file
   (never overwrite an existing backup — append a counter).
2. Probe audio track count with ffprobe.
3. Apply the persisted preset:
   - **Boost**: normalize to -14 LUFS without denoising.
   - **Boost + Denoise**: DeepFilterNet followed by -14 LUFS normalization.
   - **Gentle Boost + Denoise** (default): DeepFilterNet followed by -16 LUFS normalization.
4. Run `loudnorm` after cleanup — output has a single audio track.
5. When enabled, add natural 0.25-second audio fades after normalization. Skip
   fades for clips shorter than 0.5 seconds or when duration is unavailable.
6. Video stream is copied untouched; audio is re-encoded AAC.
7. Replace the original file in place.

Multiple dropped files process sequentially.

## Decisions

| Decision | Choice |
|---|---|
| Scope | Compact drop utility with measured, click-to-play A/B comparison; not an editor. |
| Processing | One persisted preset menu combines loudness target and denoising. |
| Compare | Session-only final preset-menu item creates all three variants without changing the source. |
| Measurements | EBU R128 envelope and integrated LUFS plus a confidence-gated estimated SNR. |
| Playback | Click a compact measured curve to play it. Switching curves preserves the timestamp; clicking the active curve pauses or resumes. |
| Audio fades | Persisted Settings toggle, enabled by default. Uses 0.25-second `qsin` curves. |
| ffmpeg | Use Homebrew ffmpeg (`/opt/homebrew/bin`, fallback `/usr/local/bin`). If missing, fail gracefully with instructions: `brew install ffmpeg`. |
| AI model | Bundle pinned DeepFilterNet 0.5.6 executables for Apple Silicon and Intel plus the DeepFilterNet3 ONNX model. Run locally with an 18 dB attenuation limit and delay compensation. |
| When done | Post a notification and remain open for waveform playback, metric inspection, and native-toolbar Undo. |
| Sandbox | Disabled. Required for in-place writes anywhere on disk; OneDrive access triggers a one-time macOS permission prompt. |
| Accepted types | Movies and audio files (`public.movie`, `public.audio`). |

## Non-goals

- No editing, trimming, format conversion, or batch folder watching.
- No arbitrary parameters or additional presets beyond Full and Gentle.
- No App Store distribution / notarization (personal tool).

## Error handling

- ffmpeg/ffprobe not found → item fails with "ffmpeg not installed — run:
  brew install ffmpeg" in the status list.
- ffmpeg non-zero exit → item shows the tail of stderr; original file untouched
  (backup is removed again so re-running stays clean).
- App never quits while a file is processing.
