# Scrolling Bible — iOS

The iOS reader for the World English Bible, sharing the `gcoreapps-backend`
Pro backend with the Android apps. This repo starts with the Bible edition;
additional scripture editions can be added as their content rights are cleared.

## Status

- SwiftUI reader with vertical paging, book/chapter picker, search, favorites,
  notes, themes, and text-size settings.
- StoreKit 2 subscriptions (`pro_monthly`, `pro_yearly`) with server-side
  verification through `verifyProPurchase` (`platform: "ios"`).
- Firebase Auth (Google and Sign in with Apple) and App Check (App Attest in
  release, debug provider in debug).
- AdMob banner and interaction-triggered interstitial gated by UMP consent.
  Google test IDs are used until production iOS ad units exist.
- Local StoreKit configuration for simulator testing.
- Offline edition bundled from the reviewed World English Bible JSON.

Signing, Firebase, App Store products, and production ad units still require an
Apple Developer account. See [TODO.md](TODO.md).

## Layout

```
scrolling-scripture-ios/
├── project.yml                     # XcodeGen spec (source of truth)
├── ScrollingScripture.xcodeproj    # generated; do not hand-edit
├── ScriptureCore/                  # platform-neutral Swift package + tests
│   ├── Sources/ScriptureCore/      # parsing, navigation, search, ads, Pro model
│   └── Checks/                     # runnable checks without Xcode
├── App/
│   ├── Sources/                    # SwiftUI app, Firebase, StoreKit, AdMob
│   ├── Resources/                  # edition JSON, assets, StoreKit config
│   ├── Info.plist
│   └── ScrollingBible.entitlements
└── tools/sync-content.sh
```

## Build

Requires Xcode 16+ and iOS 17+.

```sh
brew install xcodegen
xcodegen generate
open ScrollingScripture.xcodeproj
```

Select the `ScrollingBible` scheme. For local StoreKit testing choose
**Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration**
and pick `Configuration.storekit` (already set by the generated scheme).

The Swift package can be checked from the command line even without Xcode:

```sh
cd ScriptureCore
swift run CoreChecks
```

With Xcode installed, `swift test` runs the XCTest suite.

### Signing

Set your team in Xcode (Signing & Capabilities) or set `DEVELOPMENT_TEAM` in
`project.yml`. The app declares the **Sign in with Apple** capability. Without an
Apple Developer account, simulator builds can still compile, but Sign in with
Apple and App Attest will not work.

## Firebase setup

1. Register the bundle ID `com.gcoreapps.scrollingbible` in the shared Firebase
   project and add the iOS app.
2. Download `GoogleService-Info.plist` into `App/Resources/` (gitignored).
3. Add the reversed client ID from that plist as a URL scheme in `App/Info.plist`,
   replacing `REPLACE_WITH_REVERSED_CLIENT_ID`.
4. Set the Firebase App ID as `FIREBASE_APP_ID_BIBLE` in the backend deployment
   (the backend also serves Android, so this env var is shared).
5. Enable Google sign-in in Firebase Authentication, and enable the Sign in with
   Apple provider. Add the Apple team/bundle configuration in Firebase.
6. Enable App Check for the iOS app. Release builds use App Attest; debug builds
   use the debug provider. Register the debug token in Firebase when prompted.

`FirebaseRuntime` is fail-soft: if `GoogleService-Info.plist` is absent, the
reader still works and Pro/sign-in show a configuration message.

## App Store subscriptions

Create a subscription group named **Pro** with:

| Product ID | Period |
| --- | --- |
| `pro_monthly` | 1 month |
| `pro_yearly` | 1 year |

Configure prices and localizations in App Store Connect. The backend
allow-lists exactly these IDs per app.

The client sets `Product.PurchaseOption.appAccountToken` with a random UUID kept
in the Keychain. The backend reads it from Apple's signed transaction and binds
the purchase to the signed-in Firebase account. Transactions without a token are
rejected — this is intentional.

## Backend verification

The iOS client calls:

```json
{
  "appId": "bible",
  "platform": "ios",
  "productId": "pro_monthly",
  "transactionId": "2000000000000001"
}
```

The backend signs an App Store Server API JWT and verifies the transaction
against Apple. The client never grants Pro from StoreKit's local state alone.

Configure `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`, and the
`APP_STORE_PRIVATE_KEY` secret in `gcoreapps-backend`. Until those are set, iOS
verification fails closed.

## Ads and consent

`AdsManager` requests UMP consent before any ad request. Banner and interstitial
IDs are read from `Info.plist` (`AdMobBannerUnitID`, `AdMobInterstitialUnitID`,
`GADApplicationIdentifier`). Replace the Google test IDs with production values
before release.

The interstitial policy mirrors Android in `ScriptureCore/ProAndAds.swift`:
12 page changes, a 5-minute cooldown, and at most 2 per app session. Pro users
never load ads.

Configure the UMP privacy message in AdMob. The settings screen exposes
**Ad privacy options** when UMP requires it.

## Content

The bundled `App/Resources/world_english_bible.json` is copied from the Android
edition and is public-domain World English Bible text. Regenerate from the
canonical source when it changes:

```sh
tools/sync-content.sh ../scrolling-scripture-android/app/src/bible/assets
```

Attribution is in `App/Resources/ATTRIBUTION.md`. Do not add an edition until
its rights and editorial review are complete.

## Verification before release

- [ ] `swift run CoreChecks` passes.
- [ ] `xcodebuild -scheme ScrollingBible -destination 'generic/platform=iOS Simulator' build` succeeds.
- [ ] Backend `npm test` passes.
- [ ] StoreKit sandbox purchase, renewal, cancel, and restore all produce the
      expected server entitlement.
- [ ] App Check is enforced for the iOS app.
- [ ] UMP consent appears on a fresh install and no ad is requested before it.
- [ ] Production AdMob and App Store product IDs replace all placeholders.
- [ ] Privacy nutrition labels and the App Store listing are complete.
