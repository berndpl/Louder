# Louder project page design

## Project identity

Louder is a focused macOS utility for turning rough screen recordings into shareable video assets. Its one-line promise is: drop a video and the voice gets loud and clear in one step.

Audience: people who make quick demos, screen recordings, or internal video assets and need local, private audio cleanup without opening an editor.

## App icon source and treatment

The Website uses the real Louder app icon from `docs/blog/img/icon.png`, derived from the project app icon assets (`AppIcon.png` / `AppIcon.icon`). The icon is a leaf mark and should stay tied to Louder's "organic cleanup" identity.

Do not replace the icon with a generic audio symbol. Do not fake a glass treatment for the Website. Favicons are generated from the same local icon asset.

## Accent, palette, and type

The current page identity is a calm, notebook-like light theme with local Inconsolata fonts. The primary accent is `#1f3df2`, recorded in CSS as Catppuccin Latte blue, used for headings, links, selected tabs, and primary actions.

Preserve the blue accent unless the app identity changes. Louder's UI screenshots can use their own product colors; the Website shell should stay quiet around them.

## Family contract

Family contract version applied: `2026-07-09`.

Local family decisions:

- Keep the Website self-contained: local CSS, local fonts, local icons, and local screenshots.
- Keep external links only for GitHub releases, commit references, credits, license, and contact links.
- Keep `#posts` on the home page as the changelog migration key.

## Hero story and media rationale

The hero story is practical and direct: a janky screen recording becomes a clear, shareable asset after one drag-and-drop action. Keep the copy centered on the result, not on audio-engineering detail.

Hero media is a three-state real screenshot carousel:

- `img/hero-drop.png` shows the initial drop state.
- `img/hero-studio.png` shows the processing controls.
- `img/hero-compare.png` shows comparison before choosing a keeper.

Do not refresh product screenshots from this family-apply flow; `project-site-update` owns screenshot refreshes.

## Section hierarchy

- Hero: product promise, icon, CTAs, and screenshot carousel.
- Features / Presets tabs: explain the workflow and the local processing presets without adding another long section.
- Changelog: newest-first project history retained inline under `#posts`.
- Thank you: compact credits for the local audio, font, icon, and Swift ecosystem.

## Screenshot inventory and capture notes

Current Website screenshots are real project images stored under `docs/blog/img/`:

- `hero-drop.png`
- `hero-studio.png`
- `hero-compare.png`
- `og.png`
- `icon.png`

The hero screenshot aspect ratio is `1144 / 1004` and is mirrored in CSS for the carousel and thumbnails.

## Decisions made by project-site-family-apply

2026-07-09:

- Created this identity file from the existing Website before applying broad family updates.
- Preserved the Louder icon, blue accent, hero copy, screenshot carousel, features/presets module, changelog, and thank-you section.
- Added dedicated favicon outputs from the local app icon for the family favicon contract.
- Updated shared tab accessibility state without changing the visible section structure.
- Adapted the hero from a single active screenshot carousel to a Steps-style interactive screenshot stack: all three Louder screenshots stay visible, and tap, keyboard, or autoplay rotates which one leads.
- Kept the stack wrappers transparent and used alpha-aware image shadows so Louder's transparent screenshots do not sit inside visible rectangular cards.
- Kept stack screenshots fully opaque during movement and apply the new stacking order before moving positions to avoid a visible end-of-motion jump.
