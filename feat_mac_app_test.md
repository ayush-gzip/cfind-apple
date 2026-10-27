# Mac app: test record

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

## Not tested yet

- Clicking a notification to open its chat was not checked by hand.
- The "cfind is not running" screen: not seen with the daemon stopped.

## Known limits

- Close the Mac window, then click a notification: the app comes forward but may not
  reopen the window.
- Release zips are ad-hoc signed. The first time, right-click cfind.app and choose Open.
- No iPhone release: it needs a paid Apple account. Build it with Xcode instead.

## Rerun before you change this area

1. `cfindTests` on macOS and on an iOS simulator.
2. Build and install, make an agent ask for approval, check the notification arrives.
3. Run the Mac UI test with the daemon running.
