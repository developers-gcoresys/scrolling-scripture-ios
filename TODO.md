# TODO — Scrolling Bible iOS

## Launch blockers

- [ ] Create the Apple Developer account, app record, and bundle ID
      `com.gcoreapps.scrollingbible`.
- [ ] Add signing team and enable the Sign in with Apple + App Attest capabilities.
- [ ] Register the iOS app in Firebase; add `GoogleService-Info.plist` and the
      reversed-client-ID URL scheme.
- [ ] Create `pro_monthly` and `pro_yearly` subscriptions in App Store Connect.
- [ ] Create the App Store Server API key and set `APP_STORE_ISSUER_ID`,
      `APP_STORE_KEY_ID`, and `APP_STORE_PRIVATE_KEY` in `gcoreapps-backend`.
- [ ] Add App Store Server Notifications V2 to the backend so renewals/refunds
      update without an app launch.
- [ ] Replace Google test ad IDs with production AdMob iOS app/banner/interstitial
      IDs, and configure the UMP privacy message.
- [ ] Run a full sandbox purchase/restore/cancel/refund pass.
- [ ] Add app icons, screenshots, privacy labels, and the App Store listing.
- [ ] Build on a machine with Xcode; the current scaffold was generated and
      syntax-checked without Xcode.

## Next features

- [ ] Additional scripture editions (only after rights and editorial review).
- [ ] Offline Pro packs using the backend's `downloadProExplanationPack`.
- [ ] Lock-screen/home-screen verse widgets (WidgetKit).
- [ ] Daily verse notifications.
- [ ] Share-card image export.
- [ ] Better accessibility labels and Dynamic Type audit.

## Content and policy

- [ ] Confirm the World English Bible attribution wording in the listing.
- [ ] Keep explanation features disabled until content rights and output are
      reviewed for each edition.
- [ ] Confirm Apple Guideline 4.3 positioning if more editions become separate
      apps; the planned approach is one universal Scripture app.
