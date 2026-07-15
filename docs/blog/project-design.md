# Louder project page design

## Project identity

Louder is a focused macOS utility for turning rough screen recordings into shareable video assets. Its one-line promise is: drop a video and the voice gets loud and clear in one step.

Audience: people who make quick demos, screen recordings, or internal video assets and need local, private audio cleanup without opening an editor.

## App icon source and treatment

The Website uses the real Louder app icon from `docs/blog/img/icon.png`, derived from the project app icon assets (`AppIcon.png` / `AppIcon.icon`). The icon is a leaf mark and should stay tied to Louder's "organic cleanup" identity.

Do not replace the icon with a generic audio symbol. Do not fake a glass treatment for the Website. Favicons are generated from the same local icon asset.

## Accent, palette, and type

The Website uses the family light/dark palettes with local Inconsolata as the default and locally
stored JetBrains Mono as the URL-selected alternative. Louder's light accent pair is `#1f3df2` /
`#5b6dff`; its dark pair is `#89b4fa` / `#b4befe`. The blue accent is used for links, primary
actions, interactive emphasis, and the current-Website outline.

Preserve the blue accent pairs unless the app identity changes. Louder's UI screenshots can use
their own product colors; the Website shell should stay quiet around them.

## Family contract

Family contract version applied: `2026-07-15.27`.

Local family decisions:

- Keep the Website self-contained: local CSS, local fonts, local icons, and local screenshots.
- Keep external links only for GitHub releases, commit references, credits, license, and contact links.
- Keep `#posts` on the home page as the changelog migration key.
- Follow the operating-system appearance until a family theme choice is supplied by URL or storage.
- Keep only the family font and light/dark controls in the footer. Custom palettes are a non-app
  family feature; Louder always uses its recorded blue Website palette.
- Deliberately omit the family primary feature grid; Bernd chose Presets as Louder's only product module.
- Keep the custom 404 at `docs/404.html`, using the Louder icon, blue palette, family shell, and
  one action back to the Website.

## Hero story and media rationale

The hero story is practical and direct: a janky screen recording becomes a clear, shareable asset after one drag-and-drop action. Keep the copy centered on the result, not on audio-engineering detail.

Hero media is a three-state real screenshot carousel:

- `img/hero-drop.png` shows the initial drop state.
- `img/hero-studio.png` shows the processing controls.
- `img/hero-compare.png` shows comparison before choosing a keeper.

Do not refresh product screenshots from this family-apply flow; `project-site-update` owns screenshot refreshes.

## Section hierarchy

- Hero: product promise, icon, one Download action, and the three-state screenshot carousel.
- Presets: the interactive local-processing module is the sole product section after the hero.
- Recent changes: three compact home-page links under `#posts`, with complete prose on `changelog.html`.
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

2026-07-13:

- Preserved the Louder icon, blue palette, local Inconsolata type, hero story, real screenshots, Features / Presets module, changelog, and thank-you section.
- Added the shared skip link and removed the hidden topbar from keyboard and assistive-technology navigation until it appears.
- Removed shared CSS rounding from the real app icon so its own transparent-corner treatment remains intact.
- Added an accessible name to the intentionally headingless Features / Presets section.
- Updated tabs for roving focus and Arrow, Home, and End key operation.
- Paused the screenshot stack while hovered or focused and disabled autoplay for reduced-motion preferences.
- Made preset processing-step details available through focus as well as hover and click.

2026-07-14:

- Applied family contract `2026-07-14.18` and curated Project Website roster version `2026-07-14`.
- Replaced the reveal-on-scroll project header with the canonical non-sticky Notes / About header and
  Louder / Steps icon strip on every Website page.
- Vendored the canonical family theme, typography, header, footer, action styles, behavior, fonts,
  and both curated project icons under `docs/blog/`.
- Added Louder's coordinated light and dark blue accent pairs without changing the project identity.
- Preserved the real Louder icon, hero copy, three screenshots, screenshot-stack geometry and
  interaction, all four feature descriptions, preset content, credits, and complete changelog prose.
- Initially migrated the four primary capabilities into the family feature grid, then removed the
  grid at Bernd's explicit request so Presets remains the only product section after the hero.
- Removed the generic Get in touch actions because About is owned by the global header; kept Download
  for Mac as Louder's single hero product action.
- Moved the complete changelog to `changelog.html`, kept the three newest date-and-title links under
  home-page `#posts`, and labeled the final link `View Changelog`.
- Added the canonical footer theme switch and page-local accent picker without changing Louder's
  default accent pair.
- Preserved the existing focus, keyboard, pause-on-focus, reduced-motion, and preset-detail
  accessibility behavior while removing the obsolete reveal-on-scroll header script.
- Kept all three previous hero screenshots visible and expanded cycling to one transparent,
  keyboard-accessible control covering the full hero media area.
- Simplified the hero carousel to manual cycling only. Every screenshot now shares one centered
  anchor and transform origin, and movement uses a single transform transition with no autoplay.
- Contained the hero stack's paint overflow and removed inline z-index writes so cycling cannot
  expand or relayout the page scroll area.
- Moved compact changelog titles onto the family paragraph ramp (`1rem / 500 / 1.4`) instead of
  inheriting the larger default `main` size.
- Kept Presets visually headingless, moved its label into the lead sentence, and removed the
  interaction-instruction sentence.

2026-07-15:

- Applied family contract `2026-07-15.25`.
- Added the fully local JetBrains Mono variable font and URL-driven whole-page font switching.
- Kept Louder's project-owned blue light and dark palettes; the app Website ignores custom palette
  parameters and omits the non-app palette picker.
- Refreshed the canonical family typography, header, footer, theme, and action assets without
  changing product copy, screenshots, Presets content, changelog prose, or carousel behavior.
- Applied family contract `2026-07-15.26` with a custom Pages-root 404 that preserves the Louder
  identity and resolves local assets from missing URLs at any depth.
- Applied family contract `2026-07-15.27`; the shared primary action asset now supports springing
  symbols, while Louder's current text-only Download action remains unchanged.
