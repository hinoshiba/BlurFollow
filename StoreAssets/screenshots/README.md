# Screenshot drop location

Capture the five scenes defined in `../screenshot_manifest.json`. Put untouched
application captures in `raw/<locale>/`, then use `template.html` to compose a
**1440 × 900** storefront image without enlarging the raw UI beyond its native
size.

Open the template with a locale and shot number, for example:

```text
template.html?locale=ja-JP&shot=1
template.html?locale=en-US&shot=3
```

The template reads the `raw_filename` declared for each scene in the manifest, draws the localized
headline and supporting copy, and shows a conspicuous missing-source message
until the genuine capture is present. Set the browser viewport to exactly
1440 × 900 CSS pixels and capture only the canvas.

Write final files without renaming them:

```text
screenshots/ja-JP/01-window-following.png
screenshots/ja-JP/02-display-window-modes.png
screenshots/ja-JP/03-share-preview-check.png
screenshots/ja-JP/04-share-guide.png
screenshots/ja-JP/05-local-controls.png
screenshots/en-US/01-window-following.png
screenshots/en-US/02-display-window-modes.png
screenshots/en-US/03-share-preview-check.png
screenshots/en-US/04-share-guide.png
screenshots/en-US/05-local-controls.png
```

Do not add generic placeholder images: an accidentally uploaded placeholder can
reach review. Keep raw captures unchanged and regenerate every final image after
the shipping UI, copy, locale, or template changes.

The checked-in captures predate Text Follow's four match modes, its strict-safety
preference, and the independent 10 Display Pin, 5 Window Pin, and 2 Text Follow
rule allowances. Treat every existing raw and final image as a layout reference
only. Recapture all five scenes from the exact shipping build in both locales,
then regenerate every final image. In particular, shot 2 must show Text Follow as
separate from Window Pin, any visible Text Follow editor must include Exact,
Prefix, Contains, and Regular Expression. Shot 5 must focus on local data,
capture permissions, and support controls. If its safety control is visible,
show the current state accurately. The old two-mode and Settings images are
not valid for submission.

Follow [App Review Guideline 2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata):
exclude pricing and free-service claims from both screenshot captions and
visible captured UI. This includes free allowances, discounts, and one-time
purchase or unlock promotions, even without a numeric price. Select a capture
region that omits those panels while preserving the genuine UI. Inspect every
final image in every submitted locale; changing a headline does not remove
pricing text inside the app capture. Keep commerce disclosures in the app
description and purchase review notes.

Raw-to-final mapping:

| Final file | Raw app capture |
|---|---|
| `01-window-following.png` | `00-onboarding.jpg` |
| `02-display-window-modes.png` | `02-modes.jpg` |
| `03-share-preview-check.png` | `03-review-before-sharing.jpg` |
| `04-share-guide.png` | `03-share-guide.jpg` |
| `05-local-controls.png` | `04-settings.jpg` |

Validate the complete set before upload:

```sh
python3 StoreAssets/Scripts/validate_metadata.py --require-screenshots
```

The validator checks image files and dimensions; it does not read screenshot
text or establish that the captured UI is current. Visual review is required.
