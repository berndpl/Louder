# Changelog

## 1.1 (Build 4) — 2026-06-27

- Source: `2a22ec9b9438fd6c1288c81a5a11e30f04af107d`
- Marketing decision: minor — first notarized release since Build 2; bundles the user-visible capabilities accumulated since then (Clean AI cleanup preset, 4K/1080p output-quality selection, multi-channel mono downmix) plus the new mode-aware Reset control, matching the 1.1 bump flagged in the Build 3 note.
- Notarization: Accepted (`f6481dce-9571-4105-9fd0-a29ab8811f88`)
- Installed app: `/Applications/Louder.app`
- Archive: `/Users/berndplontsch/PARALocal/apps/Louder/dist/Louder-1.1-build-4-macos-arm64.zip`

### Changes

- Replaced the toolbar Undo button with a mode-aware Reset: in Compare it confirms deleting all generated files; in single-process it keeps the new louder file and asks whether to keep or delete the original, then returns to the initial drop screen.

## 1.0 (Build 3) — 2026-06-22

- Source: `53ca6e4a01c3621b2978163f3ddec861267c1424`
- Marketing decision: unchanged — kept the 1.0 milestone for this stopgap local install; the next notarized release should evaluate a 1.1 minor bump for the Clean AI preset, 4K/1080p output quality, and multi-channel downmix added since Build 2.
- Notarization: **SKIPPED** — no notarization credential available on this machine (no keychain notary profile, no App Store Connect API key). Signed with Developer ID Application + hardened runtime + secure timestamp only. Gatekeeper `spctl --assess --type execute` accepts it (source=Developer ID) for local use, but the `dist` archive is **not** notarized/stapled and is not safe to distribute. Re-run a full notarized install (Build 4+) once credentials are configured.
- Installed app: `/Applications/Louder.app`
- Archive: `/Users/berndplontsch/PARALocal/apps/Louder/dist/Louder-1.0-build-3-macos-arm64.zip`

### Changes

- Stability hardening from the audit: cancel-safe process launch (no terminate on an unlaunched Process), full batch rollback that restores replaced originals, and atomic same-volume in-place file replacement.
- README idle-state animation GIF re-rendered to match the screenshot crop and show the drop-beacon motion.

## 1.0 (Build 2) — 2026-06-20

- Source: `f060abd7170304978ff73bc484c1b848d6f16723`
- Marketing decision: unchanged — first changelog-backed install; retained the existing 1.0 milestone.
- Notarization: Accepted (`04a1f15d-7e50-4c7c-acce-b7493965bbec`)
- Installed app: `/Applications/Louder.app`
- Archive: `/Users/berndplontsch/PARALocal/apps/Louder/dist/Louder-1.0-build-2-macos-arm64.zip`

### Changes

- Added selectable local audio cleanup with DeepFilterNet, gentle FFmpeg denoising, and an unchanged loudness-only mode.
- Bundled pinned Apple Silicon and Intel DeepFilterNet executables and the DeepFilterNet3 model.
- Moved successful completion status into the central description area and improved failure-state reliability.
