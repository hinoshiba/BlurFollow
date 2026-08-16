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
