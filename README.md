# cfind-apple

[![CI](https://github.com/ayush-gzip/cfind-apple/actions/workflows/ci.yml/badge.svg)](https://github.com/ayush-gzip/cfind-apple/actions/workflows/ci.yml)

An iPhone and Mac client for the [cfind](https://github.com/ayush-gzip/context-find) dashboard. It shows your Claude Code and Codex work from your phone or your menu bar.

The Mac app shows the dashboard website in a native window and sends native notifications. The iPhone app is a native SwiftUI client.

## Features

- Sessions: live and recent transcripts, with full-text search over messages.
- Agents board: lanes for Needs input, Running, Queued and Idle. Each profile has its own mark and colour. Subagents sit under their parent.
- Chat: send messages and images, answer approvals and questions, take over a terminal session.
- Usage: limits per profile.
- Mac notifications: when an agent needs input, replies or fails, and when a terminal session finishes.

## Requirements

- The cfind daemon running on your Mac (see context-find).
- iOS 17 or newer, or macOS 14 or newer.
- For the iPhone: the Mac must be reachable over Tailscale. Run `tailscale serve --bg 4319` on the Mac. Then open Connections in the dashboard, choose Pair an iPhone, and enter the address and code in the app, or open the pairing link.

## Install

Mac:

- Download `cfind-macos-<version>.zip` from the Releases page, unzip, and move `cfind.app` to Applications. The app is ad-hoc signed, so right-click it and choose Open the first time.
- Or build it with Xcode (below) and run it.

iPhone:

- Open `cfind.xcodeproj` in Xcode. Sign in with a free Apple ID, choose your team in Signing, and turn on Developer Mode on the phone.
- Run the `cfind` scheme on the phone.
- A free Apple ID installs expire after 7 days. Run it again to reinstall.

## Build and test

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# build
xcodebuild build -project cfind.xcodeproj -scheme cfind -destination 'platform=macOS'
xcodebuild build -project cfind.xcodeproj -scheme cfind -destination 'generic/platform=iOS Simulator'

# unit tests (no daemon needed)
xcodebuild test -project cfind.xcodeproj -scheme cfind -destination 'platform=macOS' -only-testing:cfindTests
xcodebuild test -project cfind.xcodeproj -scheme cfind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:cfindTests
```

The UI tests in `cfindUITests` need a running daemon and a real Claude, so CI does not run them. See `feat_iphone_app_test.md` and `feat_mac_app_test.md` for how to run them and what was checked.

To redraw the app icon: `swift tools/make-icon.swift cfind/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

## CI and releases

CI builds both platforms and runs the unit tests on every push and pull request to `main`. Pushing a tag like `v1.0.0` builds the Mac app and attaches a zip to a GitHub Release. The iPhone app has no release build, because that needs a paid Apple account.

## License

MIT. See `LICENSE`.
