# BlurFollow brand-asset provenance

Last recorded: 2026-08-16

This record covers `BlurFollowIcon-Source.png` and the PNG renditions generated
from it under `BlurFollow/Resources/Assets.xcassets/AppIcon.appiconset/`.

## Generation record

- Creation mode: reference-guided raster redesign, followed by one targeted
  edit of the generated image. The previous in-repository icon was supplied
  only as a concept and palette reference; no external artwork was supplied.
- Generator: OpenAI image generation available in the Codex workspace.
- Previous/reference source SHA-256:
  `4b6b0c37784e6cc5509733259077c64b4c492e4d58a4eb65443420fc01051a89`
- Source SHA-256:
  `a981582cf26a04bcc70684f5b9b865a5b3e732ad33ff61e360130b37de5cee86`
- Redesign prompt:

  > Use case: logo-brand. Asset type: production master artwork for a macOS app
  > icon, square 1024-style composition intended for system-applied
  > rounded-corner masking. Image 1 is the existing BlurFollow icon; use it only
  > as a reference for the product concept and ink/cyan/iris palette. Replace
  > the entire over-rendered artwork with a cleaner redesign. Create a simple,
  > memorable "following mask" symbol for BlurFollow, a Mac utility that keeps
  > a rectangular blur region aligned to a moving app window. Use a full-bleed
  > deep ink/navy square background with a subtle cyan-to-iris tonal gradient;
  > no pre-masked squircle or black outer corners. Show one dominant front-facing
  > rounded-rectangle app-window frame, one short offset echo of that frame
  > behind it, and one bold frosted rounded blur band anchored horizontally
  > inside the foreground window. Use minimal vector-friendly flat 2.5D
  > geometry, crisp defined edges, restrained translucency, orthographic
  > composition, generous safe-area padding, at most three foreground shapes,
  > and strong 16 px readability. Use carbon/ink, cyan `#42D9C8`, iris
  > `#7C6CFF`, and soft ice-white only. No text, letters, watermark, mockup,
  > device frame, traffic-light controls, arrow, perspective tilt, extra
  > windows, floating badge, shield, lock, eye, checkmark, pin, warning, camera,
  > crop corners, glossy AI rendering, neon bloom, fuzzy edges, texture noise,
  > or pre-rounded outer tile.

- Targeted edit prompt:

  > Change only the frosted rounded blur band inside the foreground window.
  > Reduce its height to about 22% of the foreground window's interior height
  > while keeping its width and horizontal centering. Make it translucent ice
  > glass instead of opaque white, with a restrained soft cyan-to-iris blur
  > inside. Let the dark window interior faintly show through so the band feels
  > anchored inside the window. Keep the full-bleed square navy background,
  > exact front and rear frame geometry, positions, orthographic composition,
  > palette, padding, crisp edges, and all other elements unchanged. Preserve
  > 16 px readability. Add no text, arrow, controls, symbols, watermark, new
  > objects, outer rounded tile, black corners, excessive glow, or fuzzy edges.

The final generator output was resized from 1254 x 1254 to the canonical opaque
1024 x 1024 RGB source with ImageMagick 7.1.2-27 using Lanczos resampling. The
asset-catalog and website files are resized renditions of that source. Duplicate
hashes at equivalent pixel dimensions are expected. Recreate and record hashes
if the master artwork changes.

## Official branded release gate

This record documents process; it does not itself establish copyright,
trademark availability, originality, or exclusive rights. The public source
repository includes the current artwork to document and reproduce the working
UI; that publication is not a claim of ownership, clearance, or exclusivity.
Before an official branded binary distribution or any paid release, the
publisher must:

1. confirm that its agreement with the generation provider permits the planned
   commercial use and assignment/registration strategy;
2. run reverse-image and trademark/design searches and obtain professional
   clearance for the final production mark;
3. record the human or legal entity that owns or is licensed to use the asset;
4. retain the prompt, source file, hashes, review evidence, and any later human
   design files in the private release provenance archive; and
5. update `TRADEMARKS.md` and `THIRD_PARTY_NOTICES.md` if the ownership or
   upstream-material conclusion changes.

The artwork is a reserved Brand Asset under `TRADEMARKS.md`; it is not offered
under the repository's Apache-2.0 code license.
