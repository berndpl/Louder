# Design QA — Full-window Drop Surface

- Source visual truth: `/Users/berndplontsch/Library/Application Support/CleanShot/media/media_4Ce3poMoNb/CleanShot 2026-06-19 at 19.45.23@2x.png`
- Idle implementation: `/Users/berndplontsch/Library/Mobile Documents/com~apple~CloudDocs/Documents/Sparks/Screenshots/Progress/Louder/20260619_195754-louder-full-window-idle.png`
- Processing implementation: `/Users/berndplontsch/Library/Mobile Documents/com~apple~CloudDocs/Documents/Sparks/Screenshots/Progress/Louder/20260619_195838-louder-full-window-processing.png`
- Branded idle implementation: `/Users/berndplontsch/Library/Mobile Documents/com~apple~CloudDocs/Documents/Sparks/Screenshots/Progress/Louder/20260619_200214-louder-app-foreground-idle.png`
- Branded processing implementation: `/Users/berndplontsch/Library/Mobile Documents/com~apple~CloudDocs/Documents/Sparks/Screenshots/Progress/Louder/20260619_200254-louder-app-foreground-processing.png`
- Expanded-border implementation: `/Users/berndplontsch/Library/Mobile Documents/com~apple~CloudDocs/Documents/Sparks/Screenshots/Progress/Louder/20260619_200541-louder-expanded-border.png`
- Comparison image: `/tmp/louder-window-comparison.png`
- Viewport: native macOS window, 380 points wide, light appearance
- States: idle with Gentle/Fades; active processing with controls hidden

## Full-view comparison evidence

The annotation asks to remove the external Loudness label, LUFS caption, and backup footer and move controls into the drop surface. The implementation goes further per the follow-up brief: the title text and titlebar band are removed, native traffic lights remain, and the dashed surface expands across the full active window area.

## Focused region comparison evidence

A separate crop was unnecessary because the side-by-side comparison renders the window chrome, drop prompt, controls, and dashed boundary at readable 2× density. The processing screenshot separately verifies the filename, status, and progress-bar state.

## Findings

- No actionable P0, P1, or P2 mismatches.
- Typography uses the same native macOS system hierarchy as the source.
- Spacing uses the whole window while leaving clearance around the traffic lights.
- Colors and state treatments remain native and semantic.
- The app-icon foreground layers are composed into a transparent branded asset with their original burgundy tint and opacity hierarchy.
- Idle copy is reduced to the drop instruction and functional labels.
- Processing hides controls and replaces them with filename, operation status, and a native indeterminate progress bar.

## Patches made

- Enabled full-size content beneath a transparent, title-hidden titlebar.
- Expanded the dashed drop surface to fill the window.
- Added distinct idle and processing presentations inside the same surface.
- Hid settings while processing and added an indeterminate progress bar.
- Replaced generic SF Symbols in both states with the app icon's foreground illustration.
- Expanded the dashed perimeter to the window edge and left an open notch around the native traffic lights.

## Follow-up polish

- None required.

final result: passed
