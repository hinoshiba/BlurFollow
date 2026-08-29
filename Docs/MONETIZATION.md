# Unlimited Masks purchase design

Decision date: 2026-08-26
First plan-limited version: 0.2.0

## Product boundary

The official Mac App Store build has three independent saved-item allowances at
no charge. A single, permanent non-consumable In-App Purchase removes all of
BlurFollow's creation limits:

| | Free | Unlimited Masks |
| --- | ---: | ---: |
| Saved Display Pins | 10 | No app-imposed plan limit* |
| Saved Window Pins | 5 | No app-imposed plan limit* |
| Saved Text Follow (Beta) rules | 2 | No app-imposed plan limit* |
| Frost, Mosaic, Redact, editing, reconnect, and on/off controls | Included | Included |
| Share Preview and every safety/verification control | Included | Included |
| Billing | None | One-time purchase |

Text Follow's Beta label does not change this commerce contract: two saved rules
remain included at no charge, and a verified Unlimited Masks entitlement removes
that creation limit together with the Display and Window limits. Existing rules
and every safety/verification control remain available regardless of entitlement
or Beta status.

\* Practical capacity remains finite and depends on the Mac, WindowServer, and
the size and visual effect of each mask, the number of active capture streams,
and on-device OCR cost.

- Product ID: `com.hinoshiba.blurfollow.unlimited_masks`
- Type: Non-Consumable
- Reference name: `BlurFollow Unlimited Masks`
- Family Sharing: off until the release owner makes a separately reviewed,
  effectively irreversible decision to enable it
- Store price: configured in App Store Connect and always rendered from
  `Product.displayPrice`; no currency or amount is hardcoded in shipping UI
- App Store Connect launch price: ¥500 / US $4.99,
  subject to the publisher's approval and Apple's current storefront tiers

The 10 Display / 5 Window / 2 Text Follow thresholds are product hypotheses, not
measured facts. They leave common display and one-window workflows fully usable
while accounting for the substantially higher runtime cost of live capture and
OCR. Revisit them only with aggregate App Store Connect analytics and support
feedback; no analytics SDK is added to the app.

Every saved definition counts exactly once in its own category, regardless of
Frost/Mosaic/Redact style or enabled state. A Text Follow rule counts once even
when the same pattern matches zero, one, or many blocks on screen; Exact, Prefix,
Contains, and Regular Expression use the same single-rule accounting. Runtime OCR
matches and generated overlay panels never consume additional plan slots.
Counting only Mosaic, enabled definitions, or current detections would make the
limit inconsistent and trivially avoidable. Deleting an item reopens one slot
in that category; unused slots do not transfer between categories.

## Existing-user and safety contract

Version 0.1.1 offered unlimited masks. A verified
`AppTransaction.originalAppVersion` earlier than 0.2.0 therefore grants
permanent grandfathered unlimited access. This is separate from the In-App
Purchase entitlement and is never inferred from a mutable local Boolean.

The plan boundary controls only creation:

- Never delete, disable, hide, reorder, or alter an existing mask because an
  entitlement is checking, missing, refunded, or revoked.
- A person above a current category limit can still view, edit, move, reconnect,
  enable, disable, export, and delete every saved mask and Text Follow rule.
- Never make Redact, Share Preview, recovery warnings, Last-position cover,
  permission guidance, or another safety/verification control paid.
- Source builds include unlimited masks so the Apache-2.0 project stays useful.
  `BLURFOLLOW_APP_STORE` enables commerce only in the official Xcode target.

If StoreKit cannot verify either grandfather status or a purchase, the app
fails closed only for a new paid-plan creation. Existing masking and sharing
workflows remain unchanged.

## Purchase journey

There are two honest entry points:

1. A free user chooses Display Pin, Window Pin, or Text Follow after reaching
   that category's 10, 5, or 2-item allowance.
2. A person deliberately opens Support BlurFollow in Settings.

For a limit-triggered flow, show the purchase view before a picker or range
selector. Explain that the current masks and rules remain active, show the
localized one-time price, keep Not Now visible, and offer Restore Purchases.
After a verified purchase or restore, dismiss the sheet and resume the exact
Display, Window, or Text Follow creation the person requested. Cancellation
makes no state change and does not immediately re-present the offer.

The purchase view describes feature value first and development support second.
It does not describe the transaction as a charitable donation, subscription,
sale, discount, countdown, or unlimited hardware capacity.

## StoreKit implementation contract

The implementation is in:

- `BlurFollow/Services/PurchaseManager.swift`
- `BlurFollow/Models/MaskAccessPolicy.swift`
- `BlurFollow/Views/UnlimitedMasksView.swift`
- `Config/BlurFollow.storekit`

Requirements:

- Start listening to `Transaction.updates` before the initial asynchronous
  entitlement check.
- Treat only a verified, non-revoked transaction matching the exact product ID
  as a purchase entitlement.
- Check `Transaction.currentEntitlements` on launch, purchase, restore, and
  relevant transaction updates.
- Check a verified `AppTransaction` for the pre-0.2.0 grandfather rule.
- Finish every handled verified transaction after delivering access. Never
  grant or finish an unverified transaction.
- Treat user cancellation as a neutral outcome and pending approval as a state
  that later completes through transaction updates.
- Call `AppStore.sync()` only from an explicit Restore Purchases action because
  it may request Apple Account authentication.
- Keep product loading separate from entitlement verification. A failed price
  request must not remove verified access.
- Never store `isUnlimited` in `Masks.json` or UserDefaults as an entitlement
  source.
- Enforce the independent limits inside `MaskStore.add` / `addTextRule` and also
  check before opening an asynchronous picker. A rejected Window Pin or Text
  Follow rule must not leave a tracker binding or capture stream.

The checked-in StoreKit Configuration is a local test fixture. App Store
Connect remains authoritative and must be configured separately with the exact
same identifier, type, and localizations.

## Rating and discovery design

Ranking cannot be guaranteed and must never be manipulated. BlurFollow asks the
system to consider a rating prompt only after at least two successful Share
Preview position checks and seven days of use, no more than once per marketing
version, and at least 120 days after the preceding app-side request. Share
Preview only records the successful task; the prompt waits until the main app
window next becomes key after capture has stopped, and remains suppressed while
a picker, range selector, onboarding, or purchase surface/operation is active.

This policy is identical for free, purchased, and grandfathered users. The app
does not ask for sentiment first, route only positive users to the App Store,
reward reviews, connect reviews to an unlock, or show its own rating form. A
persistent, explicit Rate BlurFollow link and support link remain in Settings.

Store metadata uses accurate, non-duplicated search terms and discloses the
10 Display / 5 Window / 2 Text Follow allowances and that creation beyond them
uses a one-time purchase. Category selection remains Utilities/Productivity;
relevance is not traded for rank.

## Release and test gates

Before submission, configure the Non-Consumable in App Store Connect, attach
the first In-App Purchase to the 0.2.0 submission, upload its review screenshot,
and confirm the Paid Apps Agreement, tax, banking, price, territories, and
localizations. These are authorized release-owner actions and are not completed
by this source change.

Test in Xcode StoreKit Configuration, Sandbox, and TestFlight:

- 0 through 10 Display Pins, 0 through 5 Window Pins, and 0 through 2 Text
  Follow rules, including each category's next-item gate;
- multiple simultaneous OCR blocks from one Text Follow rule still consuming
  exactly one saved-rule slot;
- purchase success, cancellation, failure, Ask to Buy/pending, relaunch, and a
  purchase completed on another device;
- explicit restore with and without a matching purchase;
- product-load failure, offline launch, refund, revocation, and reinstallation;
- grandfathered 0.1.1 users and new 0.2.0 users;
- existing masks above the limit after entitlement loss;
- Japanese/English prices, copy, keyboard navigation, and VoiceOver; and
- review-prompt timing with purchase and picker UI absent.

Primary Apple references:

- [In-App Purchase with StoreKit](https://developer.apple.com/documentation/storekit/in-app-purchase)
- [Transaction.currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
- [AppStore.sync()](https://developer.apple.com/documentation/storekit/appstore/sync%28%29)
- [Supporting business model changes](https://developer.apple.com/documentation/storekit/supporting-business-model-changes-by-using-the-app-transaction)
- [Requesting App Store reviews](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
