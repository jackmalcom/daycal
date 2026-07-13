# daycal

Your calendar, at a glance.

<img width="311" height="226" alt="Screenshot 2026-01-16 at 4 08 00 PM" src="https://github.com/user-attachments/assets/cc7cebe8-4ac4-4edc-bdff-7bdc3a8a7054" />

## 🚧 This is a beta! 🚧

This app currently relies on testing oauth, and is _**not**_ notarized. To disable the warning that prevents you from running the app, run `xattr -dr com.apple.quarantine /Applications/Daycal.app` in your terminal after copying the .dmg to your Applications folder. To sign in, you either need to be added to the official testing oauth, or create your own as mentioned below.

> **Note on re-auth:** while the Google Cloud OAuth consent screen is in **Testing** publishing status, Google expires refresh tokens after 7 days, forcing a new sign-in every week. Publishing the consent screen to **Production** (no verification needed for personal use — sign-in just shows an "unverified app" interstitial once) makes refresh tokens long-lived.

## Build

- Open `Daycal.xcodeproj` in Xcode
- Update OAuth values in `Sources/Daycal/GoogleOAuthConfig.swift`
  - You only need calendar readonly permissions
- Build + Run the `Daycal` target

_Built with [OpenCode](https://opencode.ai/) and GPT 5.2_
