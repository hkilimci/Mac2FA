# Mac2FA — Development Plan

A native macOS 2FA app that works fully offline and is compatible with Google
Authenticator. It is a **companion**, not a replacement: TOTP codes are
deterministic from `(secret, time)`, so the same secret can live on both
Mac2FA and Google Authenticator simultaneously. Mac2FA only ever *copies* a
secret (rescan the original QR, or use Google's "Export accounts" QR, which
copies — it does not delete the account from the phone). Nothing in Mac2FA
touches, disables, or de-registers the phone app.

## Goals

- Native macOS app (SwiftUI, macOS 14+), feels like a first-party Apple app.
- 100% offline. No network entitlement, no telemetry, no account/sync server.
- RFC 4226 (HOTP) + RFC 6238 (TOTP) compatible — codes match Google
  Authenticator byte-for-byte for the same secret and clock.
- Import via QR scan, image drop, manual entry, and Google Authenticator's
  `otpauth-migration://offline?data=...` batch export.
- Secrets stored in Keychain, gated by Touch ID / password, with Secure
  Enclave–wrapped database key when available.
- Menu bar quick-access with global hotkey and click-to-copy (auto-clear).

## Non-goals (initial release)

- Cloud sync. (May add opt-in iCloud sync later, off by default.)
- Push-based 2FA (Duo / Microsoft Authenticator–style). TOTP only.
- iOS / iPadOS app. macOS only for v1.

---

## Phase 1 — Foundation

- [ ] **Bootstrap Xcode project.** SwiftUI lifecycle, macOS 14+ target,
      App Sandbox on, Hardened Runtime on, bundle id `app.mac2fa`,
      development team configured, `.gitignore` for Xcode (`DerivedData/`,
      `xcuserdata/`, `*.xcuserstate`).
- [ ] **TOTP/HOTP engine.** Implement RFC 4226 HOTP and RFC 6238 TOTP.
      Support SHA1 / SHA256 / SHA512, 6–8 digits, configurable period
      (default 30s). Pure Swift, no third-party crypto dep — use
      `CryptoKit.HMAC`.
- [ ] **Base32 codec.** RFC 4648 Base32 encode/decode, accepting Google's
      whitespace-and-lowercase-tolerant variant.
- [ ] **`otpauth://` URI parser.** Parse `otpauth://totp/Issuer:account?
      secret=...&issuer=...&algorithm=...&digits=...&period=...`. Handle
      URL-encoded label, missing-issuer fallback, HOTP counter param.
- [ ] **Google migration parser.** Decode `otpauth-migration://offline?
      data=<base64 protobuf>` (Google's batch export). Implement the
      `MigrationPayload` protobuf inline (no protoc dependency): per-account
      `secret`, `name`, `issuer`, `algorithm`, `digits`, `type`.
- [ ] **Unit tests.** RFC 6238 Appendix B test vectors must pass. Add a
      manual cross-check checklist: scan a real account on phone and Mac,
      confirm codes agree for a full minute.

## Phase 2 — Storage & Input

- [ ] **Secure storage.** Keychain (`kSecClassGenericPassword`) for secrets
      with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and an access
      control flag requiring user presence. Encrypted SQLite (or Core Data
      with NSPersistentStoreFileProtectionKey) for non-secret metadata
      (issuer, label, icon, order, tags). DB key wrapped by a Secure
      Enclave key when the Mac has one.
- [ ] **QR ingestion.**
  - Live camera scan via `AVCaptureSession` + `AVCaptureMetadataOutput`.
  - Image scan via `Vision` `VNDetectBarcodesRequest` for drag-and-drop,
    paste, and "Open with Mac2FA".
  - Optional screen-region capture (`CGWindowListCreateImage` + Vision)
    to grab a QR shown on screen during account setup.

## Phase 3 — UI

- [ ] **Accounts list.** SwiftUI `List` of accounts; each row shows
      issuer, account label, current code (monospaced, grouped 3-3),
      a countdown ring, and a copy button. Click row to copy; clipboard
      auto-clears after 30s.
- [ ] **Add / edit flows.** Sheet with three tabs: Scan QR, Import Image,
      Manual Entry. Manual entry exposes secret, issuer, account name,
      algorithm, digits, period, type (TOTP/HOTP). Folders / tags
      optional in v1.
- [ ] **Menu bar.** `MenuBarExtra` scene with search field and a compact
      list. Global hotkey (configurable, default ⌥⌘\\) to surface it.
      Main window remains optional — power users can live in the menu bar.

## Phase 4 — Security & Trust

- [ ] **Unlock.** `LocalAuthentication` with Touch ID; password fallback.
      First-run sets an app password used to derive the DB key alongside
      the Secure Enclave key.
- [ ] **Auto-lock.** Configurable idle timeout (default 5 min), lock on
      sleep, lock on lid close, lock on screensaver, lock on screen lock.
- [ ] **Offline posture.** Remove `com.apple.security.network.client`
      entitlement. No URLSession usage in production target. Add a CI
      check that greps the build for `URLSession`. Document this in
      README.

## Phase 5 — Interop & Polish

- [ ] **Import / export.**
  - Export: AES-GCM encrypted JSON, password-derived key (Argon2id or
    PBKDF2-SHA256 with high iteration count).
  - Import: Mac2FA JSON, Google migration QR, optional Aegis JSON,
    2FAS JSON, Authy export.
- [ ] **Accessibility.** Full VoiceOver labels, complete keyboard
      navigation (⌘F search, ↑/↓ navigate, ⌘C copy, ↩ copy + close menu),
      Dynamic Type respect, sufficient contrast in both color schemes.
- [ ] **Localization scaffolding.** Wrap all UI strings in
      `String(localized:)`, ship `en` initially.
- [ ] **Assets.** App icon (all required sizes), menu bar template icon,
      empty-state illustrations, error states.
- [ ] **Ship it.** Notarize + staple, DMG for direct distribution and/or
      Mac App Store submission, Sparkle for auto-update if shipping
      outside MAS, privacy manifest (`PrivacyInfo.xcprivacy`), README
      with screenshots and the "does not affect Google Authenticator"
      explanation.

---

## Tech choices (locked in)

| Concern        | Choice                                              |
| -------------- | --------------------------------------------------- |
| Language       | Swift 5.9+                                          |
| UI             | SwiftUI                                             |
| Min OS         | macOS 14 (Sonoma)                                   |
| Crypto         | `CryptoKit` (HMAC, SHA, AES-GCM)                    |
| QR scan        | `AVFoundation` (live) + `Vision` (images)           |
| Secrets        | Keychain + Secure Enclave–wrapped DB key            |
| Persistence    | SQLite via GRDB *or* Core Data (decide in Phase 2)  |
| Biometrics     | `LocalAuthentication`                               |
| Auto-update    | Sparkle (only if shipping outside MAS)              |
| Tests          | XCTest                                              |

## Open questions

1. SQLite (GRDB) vs Core Data for metadata? GRDB is simpler and easier to
   encrypt end-to-end; Core Data integrates better with SwiftUI `@FetchRequest`.
2. Ship via Mac App Store, direct DMG, or both? MAS gives easier install
   but forbids Sparkle and adds review friction.
3. Hotkey library: roll our own with `Carbon.HIToolbox` or pull in
   `KeyboardShortcuts` SPM package.
