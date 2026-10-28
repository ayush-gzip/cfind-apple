# Mac app: test record

## 2026-10-28: Option-Command-F

- View > Full Screen moved from Shift-Command-F to Option-Command-F, matching the
  dashboard help (Codex change).
- It still did nothing in the running app. A WebKit probe (menu item on ⌥⌘F, page
  focused) showed the menu does get ⌥⌘F, so the cause was not found. Now the page
  matches `e.code === "KeyF"` with ⌘⌥ (Option turns the key into "ƒ"), stops the
  event and posts `window:fullscreen`; the app toggles `view.window`, its own window,
  instead of `NSApp.keyWindow`. The menu item uses the same window.
- WebKit probe (WKWebView, `-AppleShowScrollBars Always`, zoom 1.3): the page posts
  `window:fullscreen` on ⌥⌘F. Not checked in the installed app yet.
- Needs the app rebuilt and reinstalled; an older app ignores the message.

## Scope

The same `cfind` target runs on macOS 14 or newer. The window is the dashboard website
from the daemon in a `WKWebView` (`cfind/WebDashboard.swift`), loaded from
`http://127.0.0.1:<port>/?t=<token>` in the daemon's service file. The app adds the Dock
icon, ⌘N (new agent) and Mac notifications when an agent needs input or a terminal
session finishes. The iPhone screens are iOS only. The daemon and website are in the
context-find repo.

The page talks to the app in two ways:
- The app calls `window.cfindOpen(kind, id)` when a notification is clicked.
- The page posts the open chat (`agent:<id>`, `session:<path>` or empty) to the `cfind`
  message handler, so the app shows no banner for the chat on screen.
- The page also posts `window:drag` (mouse down on an empty part of its top row),
  `window:zoom` (double-click there) and `theme:dark` / `theme:light` (its own theme).
- The app puts class `mac-app` on `<html>` and sets `--mac-lights` (left inset past the
  window buttons) and `--mac-bar` (top row height), in CSS px, at document start and on
  zoom, resize and full screen.

## Build and run

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project cfind.xcodeproj -scheme cfind -destination 'platform=macOS' build
```

Unit tests (no daemon needed):

```sh
xcodebuild test -project cfind.xcodeproj -scheme cfind \
  -destination 'platform=macOS' -only-testing:cfindTests
```

UI test against the real daemon on this Mac (page loads, ⌘N, ⌘B):

```sh
xcodebuild -project cfind.xcodeproj -scheme cfind \
  -destination 'platform=macOS' -resultBundlePath ui.xcresult test \
  -only-testing:cfindUITests/CfindMacUITests
xcrun xcresulttool export attachments --path ui.xcresult --output-path ui-att
```

CI commands (what `.github/workflows/ci.yml` runs, signing off):

```sh
xcodebuild build -project cfind.xcodeproj -scheme cfind -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project cfind.xcodeproj -scheme cfind -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
xcodebuild test -project cfind.xcodeproj -scheme cfind -destination 'platform=macOS' \
  -only-testing:cfindTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
```

## Unit tests (`cfindTests`, 2026-10-27)

| platform | result |
| --- | --- |
| macOS | 20 tests, 0 failures (notification rules 9, decoding 5, helpers 6) |
| iPhone 17 Pro simulator | 36 tests, 0 failures (adds Markdown 7, model and subagent grouping 5, board lanes 1, pairing links 3) |

Notification rules: 28 checks in the old `tools/notify-rules-test.swift` (28/28 pass),
now 9 XCTest cases with the same assertions (all pass). Both runs also pass with signing
off (ad-hoc on macOS, none on the simulator), as CI runs them.

## Real run (2026-10-27, real daemon)

| # | step | result |
| --- | --- | --- |
| M1 | `CfindMacUITests.testStartAgentApproveAndReply`: new agent, Allow once, reply `42`, Return-to-send follow-up `15` | Pass |
| M2 | screenshots of Sessions, Agents and Usage in light and dark | Taken |
| M3 | install at `/Applications/cfind.app` (Release, team-signed). A dashboard agent asks for Write approval | Notification "Claude needs your input", body is the agent title plus ": Write". Seen in the Notification Center database. Pass |
| M4 | an open terminal session finishes | Notification "Claude finished". Seen in the Notification Center database. Pass |
| M5 | iPhone `testBoardUsageAndFullTextSearch` after the profile change | Profile marks and colours (Default orange, Personal purple, Codex blue); subagents sit under their parent in Active sessions and on the Agents board. Pass |

M1 and M2 ran on the old SwiftUI Mac screens, which the web wrapper replaced.

## Web wrapper (2026-10-27, real daemon)

| # | step | result |
| --- | --- | --- |
| M6 | `CfindMacUITests.testDashboardLoadsAndShortcutsWork`: the web view loads the dashboard, ⌘N opens the new agent form, ⌘B hides and shows the sidebar | Pass |
| M7 | Release build installed at `/Applications/cfind.app`, window screenshot | The dashboard with the glass sidebar and the new icon. Pass |
| M8 | Headless Chrome with a stub `window.webkit.messageHandlers.cfind`: open a chat, press Escape | Posts `session:<path>`, then empty. Pass |
| M9 | Headless Chrome: the Agents board | Subagents start folded ("3 subagents"); unfolded stays open across board redraws. Pass |
| M10 | Unit tests after the iPhone screens became iOS only | macOS 20/20, iOS 36/36. Pass |
| M11 | UI test: ⌘K then Return | the command menu runs New agent; the form opens. Pass |
| M12 | UI test: ⌘= and ⌘+ zoom in, ⌘- out, ⌘0 resets | the Sessions button grows by over 10%, then returns to its first width. Zoom is kept in UserDefaults `zoom`. Pass |
| M13 | UI test: ⌘3 then ⌘1 | ⌘3 opens Sessions (its search button shows), ⌘1 goes back to Overview. No app menu takes these keys. Pass |

Finding (M11): after an earlier dialog was closed with Escape, the XCUITest
accessibility tree did not list the command menu's field, though a log inside the
app showed the menu open (`keyup Meta palette=true`) and Return ran its first item.
The test checks the result (the New agent form), not the menu's field.

## Glass window (2026-10-28)

No title bar. The window buttons sit in the middle of a 52pt top row, the window is
clear, and an `NSVisualEffectView` (`.sidebar`, behind window) shows through where the
page is transparent (its sidebar).

| # | step | result |
| --- | --- | --- |
| M14 | Probe windows with a unified `NSToolbar` (mine or the one SwiftUI adds): hit test in the top 52pt | `NSToolbarView` takes the click, so the page's top-row buttons would not work. Not used |
| M15 | SwiftUI replica: `.windowStyle(.hiddenTitleBar)`, buttons moved, hit test at (400,8), (400,26), (400,45), (120,26), (30,40) | The web view gets every click; (26,26) is the close button. Pass |
| M16 | Replica: resize the window, then key change | Without a resize observer AppKit moves the buttons back to (16,16). With it they stay centred at (26,26). Pass |
| M17 | Release build, window capture | No band at the top; buttons centred about 26pt from the top and the left. `--mac-lights` 91, `--mac-bar` 52 at zoom 1. Pass |
| M18 | Unit tests | iOS 36/36. macOS ones left to CI: they launch a second app beside the one in use. Pass |
| M19 | View → Full Screen (⇧⌘F) calls `toggleFullScreen`; the page no longer takes ⌘⇧F, so the menu gets it. Release build passes. Not run in the installed app yet |

The page did not paint in M17: windows opened on a Space that was not on screen,
so WebKit skipped drawing. Check the glass and the page together after install.

## Phone push settings (2026-10-28)

cfind > Settings (⌘,): Bark URL, encryption key, Last push, Send test. Notifier sends each
note to Bark too, at once. Away (2 minutes idle or screen locked), it also notifies for
the chat on screen. Checked with the real `PhonePush.post` against a fake
Bark server (see the iPhone file). The Settings window itself was not opened in a test:
the user's app was running.

## Not tested yet

- Window drag and double-click from the page's top row (needs the page side), and the
  synthetic mouse-up after a drag.
- Native full screen: the buttons and `--mac-lights` 0.

- Clicking a notification to open its chat was not checked by hand.
- The "cfind is not running" screen: not seen with the daemon stopped.
- Asking state (2026-10-28): "<Name> asked you" with the question as body, from the
  `ask` field. Rules covered by `cfindTests` on macOS (29 pass). Not checked as a real
  banner.

## Known limits

- Close the Mac window, then click a notification: the app comes forward but may not
  reopen the window.
- Release zips are ad-hoc signed. The first time, right-click cfind.app and choose Open.
- No iPhone release: it needs a paid Apple account. Build it with Xcode instead.

## Rerun before you change this area

1. `cfindTests` on macOS and on an iOS simulator.
2. Build and install, make an agent ask for approval, check the notification arrives.
3. Run the Mac UI test with the daemon running.
