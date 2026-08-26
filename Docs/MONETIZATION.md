# Unlimited Masks purchase design

Decision date: 2026-08-26
First plan-limited version: 0.2.0

## Product boundary

The official Mac App Store build includes five saved masks at no charge. A
single, permanent non-consumable In-App Purchase removes BlurFollow's
mask-count plan limit:

| | Free | Unlimited Masks |
| --- | ---: | ---: |
| Saved Display and Window Pins | 5 | No app-imposed plan limit* |
| Frost, Mosaic, Redact, editing, reconnect, and on/off controls | Included | Included |
| Share Preview and every safety/verification control | Included | Included |
| Billing | None | One-time purchase |

\* Practical capacity remains finite and depends on the Mac, WindowServer, and
the size and visual effect of each mask.

- Product ID: `com.hinoshiba.blurfollow.unlimited_masks`
- Type: Non-Consumable
- Reference name: `BlurFollow Unlimited Masks`
- Family Sharing: off until the release owner makes a separately reviewed,
  effectively irreversible decision to enable it
- Store price: configured in App Store Connect and always rendered from
  `Product.displayPrice`; no currency or amount is hardcoded in shipping UI
- App Store Connect launch price: ¥500 / US $4.99,
  subject to the publisher's approval and Apple's current storefront tiers

The five-mask threshold is a product hypothesis, not a measured fact. It leaves
common one-window and notification-area workflows fully usable, while the sixth
saved region is a reasonable signal of sustained use. Revisit it only with
aggregate App Store Connect analytics and support feedback; no analytics SDK is
added to the app.

Every saved region counts exactly once, regardless of Display/Window mode,
Frost/Mosaic/Redact style, or enabled state. Counting only Mosaic or enabled
masks would make the limit inconsistent and trivially avoidable. Deleting a
mask reopens one free slot.

## Existing-user and safety contract

Version 0.1.1 offered unlimited masks. A verified
`AppTransaction.originalAppVersion` earlier than 0.2.0 therefore grants
permanent grandfathered unlimited access. This is separate from the In-App
Purchase entitlement and is never inferred from a mutable local Boolean.

The plan boundary controls only creation:

- Never delete, disable, hide, reorder, or alter an existing mask because an
  entitlement is checking, missing, refunded, or revoked.
- A person above the current free limit can still view, edit, move, reconnect,
  enable, disable, export, and delete every saved mask.
- Never make Redact, Share Preview, recovery warnings, Last-position cover,
  permission guidance, or another safety/verification control paid.
- Source builds include unlimited masks so the Apache-2.0 project stays useful.
  `BLURFOLLOW_APP_STORE` enables commerce only in the official Xcode target.

If StoreKit cannot verify either grandfather status or a purchase, the app
fails closed only for a new paid-plan creation. Existing masking and sharing
workflows remain unchanged.

## Purchase journey

There are two honest entry points:

1. A free user chooses Display Pin or Window Pin while five masks are saved.
2. A person deliberately opens Support BlurFollow in Settings.

For the sixth-mask flow, show the purchase view before a picker or range
selector. Explain that the current five masks remain active, show the localized
one-time price, keep Not Now visible, and offer Restore Purchases. After a
verified purchase or restore, dismiss the sheet and resume the exact Display or
Window creation the person requested. Cancellation makes no state change and
does not immediately re-present the offer.

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
- Enforce the limit inside `MaskStore.add` and also check before opening an
  asynchronous picker. A rejected Window Pin must not leave a tracker binding.

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

Store metadata uses accurate, non-duplicated search terms and discloses that
five masks are free and additional creation uses a one-time purchase. Category
selection remains Utilities/Productivity; relevance is not traded for rank.

## Release and test gates

Before submission, configure the Non-Consumable in App Store Connect, attach
the first In-App Purchase to the 0.2.0 submission, upload its review screenshot,
and confirm the Paid Apps Agreement, tax, banking, price, territories, and
localizations. These are authorized release-owner actions and are not completed
by this source change.

Test in Xcode StoreKit Configuration, Sandbox, and TestFlight:

- 0 through 5 free masks and the sixth-mask gate for both creation modes;
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
