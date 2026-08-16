# BlurFollow App Store submission assets

This directory contains the customer-facing metadata and capture specification
for the macOS App Store listing. Japanese (`ja-JP`) is the primary language and
English (`en-US`) is the secondary language.

## Validate

From the repository root, run:

```sh
python3 StoreAssets/Scripts/validate_metadata.py
```

The default run validates every text field, UTF-8 byte limit, URL, keyword list,
manifest, and any screenshots already present. Missing screenshots are reported
as warnings while capture is in progress. Before upload, require the complete
set:

```sh
python3 StoreAssets/Scripts/validate_metadata.py --require-screenshots
```

Exit code `0` means all required checks for the selected mode passed. App Store
Connect remains the source of truth if Apple changes a limit or accepted image
size.

## Upload mapping

- Localized storefront text: `metadata/ja-JP/` and `metadata/en-US/`
- Shared app information and privacy answers: `metadata/common/`
- Screenshot filenames, scenes, and assertions: `screenshot_manifest.json`
- Final screenshot files: `screenshots/<locale>/`
- Submission gates: `SUBMISSION_CHECKLIST.md`

`ja-JP/review_notes.txt` is the canonical App Review note. The English file is
an equivalent reviewer-facing translation that can replace it when the assigned
review team requests English.

The public URLs in metadata assume deployment at `https://blurfollow.hinoshiba.com`.
Verify domain control, HTTPS, page content, and the support mailbox before
submitting the listing.

## Apple references

- [App information fields](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Upload screenshots and app previews](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
