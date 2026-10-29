# iPhone app: test record

## Scope

A native SwiftUI app for one iPhone (this repo, `cfind-apple`). It pairs with the Mac daemon and shows
the same data as the browser dashboard: sessions, agents, usage, and the chat view
with send, images, approvals and questions. It talks to the existing `/api/*` routes
with a device token; the server side is in `ts/src/devices.ts` and `ts/src/web.ts`.

## Build and run

```sh
# server side (in the context-find repo)
cd ts && npm run build && npm test
launchctl kickstart -k gui/$(id -u)/com.context-find.dashboard

# app (simulator)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project cfind.xcodeproj -scheme cfind \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing

# app icon (only after changing the drawing)
swift tools/make-icon.swift cfind/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

UI test against the real daemon. Make a pairing code first (Connections > Pair an
iPhone, or POST `/api/devices` `{"action":"pair-start"}` with the Mac token; a code
lasts 5 minutes):

```sh
TEST_RUNNER_CFIND_BASE=http://127.0.0.1:4319 \
TEST_RUNNER_CFIND_CODE=<6 digits> \
TEST_RUNNER_CFIND_CWD=<an existing folder> \
xcodebuild -project cfind.xcodeproj -scheme cfind \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath ui.xcresult test-without-building
xcrun xcresulttool export attachments --path ui.xcresult --output-path ui-att
```

The `TEST_RUNNER_` prefix is how xcodebuild passes env vars into the test process.
The app's `-cfind-reset` launch argument clears its Keychain pairing.

## Unit tests (`cfindTests`, 2026-10-27)

Pure logic, no network, no daemon. Fixtures in `cfindTests/Fixtures/` are the shapes the
daemon sends (metrics snapshot with profiles, a subagent and an open tmux session; a
workspace with a pending approval, a tool message, an image and a queued item).

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project cfind.xcodeproj -scheme cfind \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:cfindTests
```

36 tests pass on iOS (20 on macOS): notification rules (9, moved from the old
`tools/notify-rules-test.swift`), decoding (5), helpers (6), Markdown (7), model and
subagent grouping (5), agents board lanes (1), pairing links (3). The Markdown, model,
board and pairing tests are compiled for iOS only.

CI (`.github/workflows/ci.yml`) runs on every push and pull request to `main`, on a
`macos-26` runner: build for iOS Simulator and macOS with signing off, then
`cfindTests` on macOS and on the first available iPhone simulator. The UI tests are not
run in CI (they need a live daemon and Claude).

## Automated tests in context-find (Node, 98/98 pass, 2026-10-27)

| file | covers |
| --- | --- |
| `test/devices.test.ts` | pair with a code, the code works once; bearer token works on API routes; `/api/devices` and `/api/login` refuse a device ("Only from the Mac"); the token is random, only its sha256 is stored; list has no hash; revoke ends access; 5 wrong codes end the code; over 10 tries a minute gives 429; expired code; the saved tailnet Host passes the Host check; a repeated `clientId` send runs once (cached reply, 409 while in flight) |
| `test/iphone_contract.test.ts` | the metrics snapshot and a workspace agent keep every field `Models.swift` of this app decodes without a default (profile, session, agent, message, tool, queue item, pending) |

## Real end-to-end run (simulator, 2026-10-27)

`CfindUITests.testPairStartAgentApproveAndReply`, iPhone 17 Pro, iOS 27, real daemon,
Claude Default profile. Passed in 36 s.

| # | step | result |
| --- | --- | --- |
| K1 | launch unpaired, type address and code, Pair | Sessions tab loads with live sessions. Pass |
| K2 | Agents > + > folder, task "Create a file named phone.txt that contains hi. Then reply with only the result of 6 times 7." > Start | chat opens; header "Needs input"; card "Allow Write?" with the file path, `hi` preview, Decline / Allow once / Allow edits this session. Pass |
| K3 | Allow once | Write row "Done", reply bubble `42` on the left, my bubble on the right. Pass |
| K4 | type "What is 10 plus 5? Reply with only the number." > send | reply `15`. Pass |
| K5 | deep link `cfind://pair?url=…&code=…` via `simctl openurl` | iOS asks "Open in cfind?", so the scheme is registered. The fields filling after Open was not checked on screen |
| K6 | app icon | 1024x1024, no alpha; graphite background, white bubble, blue SF Rounded "c" |
| K7 | `testBoardUsageAndFullTextSearch`: Agents tab | lanes like the website: Running 1, Idle 3 (sessions open in tmux, marked with a terminal icon). Before: "No agents yet". Pass |
| K8 | Usage tab | Claude and Codex marks (the website's SVGs, template images) in the profile colours. Pass |
| K9 | Sessions search "tailscale" + Return | "Message text" section from `/api/search` lists this session (word only in message text). Before: title and folder filter only, no match. The search bar now stays visible (it hid after tab switches). Pass |
| K10 | real iPhone 17 Pro over Tailscale (mobile data or Wi-Fi) | paired with `<mac>.<tailnet>.ts.net`; works. Quad9 DNS profile on the phone blocked MagicDNS until it was set to Automatic and Quad9 was added as the tailnet's global nameserver |
| K11 | message box, Messages style (`testSessionMessageBox`, simulator, dark) | grey + in a circle, bordered field with the send arrow inside, no grey band, hint lines up with the text; send turns on after typing; nothing sent. Stop takes the send spot while a dashboard agent runs and the box is empty (not run). Pass. Installed on the iPhone 2026-10-27 |

First run failed in the test, not the app: the folder field was pre-filled with a long
path shown cut off, so a tap put the cursor mid-text and the deletes left "find/ios"
behind (agent creation then said ENOENT). The test now deletes, taps the end again,
and repeats until the field is empty.

## Not tested yet

- Subagents now fold under a "↳ N subagents" row (a `DisclosureGroup`). Unit tests pass; the UI test was not rerun after this change.
- The 7-day reinstall on the real iPhone.
- Images from the phone (PhotosPicker, JPEG resize, upload), Take over, Codex sessions,
  question cards, queued messages and Remove, unpair from the phone, revoke while the
  app is open, dark mode screenshots.
- Background behavior: iOS stops the stream when the app leaves the screen; it
  reconnects when it comes back. No push notifications on a free Apple ID.

## Live deltas and chat push (2026-10-28)

What changed:
- `API.events()` asks for `/api/events?delta=1`. `LiveMerge` turns `metrics-delta`
  and `workspace-delta` back into whole values: sessions by path (sorted newest first,
  then by path), agents as plain JSON patched like context-find `dashboard/delta.js`
  (null = field removed, `append` = streamed text). A delta that only moves the clock
  does not redraw.
- An open transcript chat uses `/api/chat-events?path=…` instead of the 2.5 s poll and
  full reload: `chat` is whole, `chat-delta` is merged by id (`Conversation.merge`,
  newest 400). It reconnects after an error (0.5 s, doubling to 10 s) and stops in the
  background. Dashboard agents still load their fixed history once.
- `Bubble` is `Equatable`, so a new message does not re-render the other bubbles.

Tests (`LiveMergeTests`, 4): `cfindTests/Fixtures/deltas.json` holds 15 frames from the
real encoder (context-find `ts/src/delta.ts` at 3e8ced9): reorder, removed field, new
and removed sessions, profile limits, a clock-only delta, token append, pending set and
cleared, tool output, agent added, removed and reordered. Each frame is checked against
the snapshot the Mac had. Also a chat-delta merge test and a token append test.

| platform | result |
| --- | --- |
| iPhone 17 Pro simulator | 40 tests, 0 failures |
| macOS | 24 tests, 0 failures |

To regenerate the fixture after a change to `delta.ts` (uses the encoder directly, no build):
`node tools/delta-fixture.ts <context-find>/ts/src/delta.ts cfindTests/Fixtures/deltas.json`

Not tested yet: the chat stream against the real daemon from the simulator or the
phone, reconnect after a daemon restart, and the delta stream over Tailscale.

## Send now, Stop, terminal view (2026-10-28)

What changed (matches the website):
- A queued message to a working dashboard agent has "Send now" beside "Remove from
  queue" (`send-now`: Claude interrupt, Codex `turn/interrupt`; the queue then runs).
- A running terminal chat shows Stop in the send spot when the box is empty (`live-stop`:
  Esc, then Ctrl+U and Backspace). After a message to a running Claude terminal chat,
  "Send now" sits next to the hint (`live-key` `send-now` = Ctrl+X Ctrl+S) until it is
  tapped or the session stops running. Not for Codex terminal chats (no such key).
- Terminal view (`TerminalCard` in `ChatParts.swift`): the tmux pane as plain text,
  read from `/api/live-screen` every second, with ↑ ↓ ← → Tab Esc ↵ buttons
  (`live-key`). It opens by itself while the session waits; the toolbar terminal button
  shows or hides it; hiding lasts until the state changes. The disabled box says
  "Answer in the terminal view above."

Harness: `tools/phone-harness.mjs` is a scratch daemon with its own HOME, data dir, port
and tmux socket, plus a fake Claude. It has one dashboard agent on "slow task" (60 s; other
prompts get "reply to <text>"). It also has a tmux session "Terminal test" whose fake
TUI draws a colour menu. Up and Down move it, Enter picks and goes running, typed text
prints "Got: …", Ctrl+X Ctrl+S prints "Sent now", and Esc prints "Stopped" and goes idle.
It prints one JSON line `{base, code, token, keysLog, sid, profile, agentId}`. Stdin takes
`reset`, `state waiting|running|idle`, `keys`, `code`, `agent`, `queue <id> <text>`, `screen`.
SIGTERM cleans everything up.

```sh
cd <context-find>/ts && node --loader ./test/typescript-loader.mjs <cfind-apple>/tools/phone-harness.mjs $PWD
# then, with base and code from its first line:
TEST_RUNNER_CFIND_BASE=<base> TEST_RUNNER_CFIND_CODE=<code> xcodebuild test-without-building \
  -project cfind.xcodeproj -scheme cfind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:cfindUITests/CfindUITests/testSendNowStopAndTerminalView
```
Start a fresh harness for each run (the agent and the menu keep their state).

| # | case (`testSendNowStopAndTerminalView`) | result |
| --- | --- | --- |
| K12 | working agent, queue "then this" | dashed bubble, "Send now" + "Remove from queue"; no Send now before. Tap: "reply to then this" at once, Send now gone. Pass |
| K13 | terminal chat waiting | terminal view opens by itself with the menu; ↓ moves ❯ to Blue; ↵ picks; the view hides when it goes running. Pass |
| K14 | terminal chat running | Stop in the empty box; "stop the ping" sent; "Send now" by the hint; tap: pane shows "Sent now", link gone; toolbar button shows the view again. Pass |
| K15 | Stop | pane shows "Stopped", session idle, Stop gone. Pass |
| K16 | light and dark screenshots | keys fit one row (↵ symbol, "Enter" wrapped before); blank rows above a short pane (a real 40-row pane fills it). Pass |

Not tested: a real Claude TUI question from the phone (the keys are the ones the website
uses, probed on Claude 2.1.312); a Codex terminal menu; the real iPhone.

## Asking state (2026-10-28)

The daemon adds an optional `ask` to agents and sessions: set when the turn ended (idle)
with a question to the user. The app shows it as a derived state, "Needs your answer"
(orange dot, "Needs input" lane, chat header). The composer still follows the raw state,
so an asking item keeps a normal idle composer. A pending approval wins over an ask.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project cfind.xcodeproj -scheme cfind \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:cfindTests \
  -derivedDataPath <scratch DerivedData>
```

| case | result |
| --- | --- |
| decoding: `ask` present, and missing (old daemon) | Pass |
| `shownState`: idle + ask is "asking"; running + ask and idle without ask are unchanged | Pass |
| `stateLabel("asking")` is "Needs your answer"; lane 0 | Pass |
| agent running to idle with ask: one "asked you" note, same id as the "replied" note | Pass |
| agent ask appears or changes while idle: note; same ask next poll, ask cleared, chat in view: none | Pass |
| agent pending approval and ask together: only "needs your input" | Pass |
| session running to idle with ask, and ask one poll after idle: "asked you"; repeat or cleared: none | Pass |

Result: 45 tests pass on iOS (was 36), 29 on macOS (was 20). Not tested: the real daemon
sending `ask`, the list and chat header on screen (no UI test run).

De-dup: the "asked you" note reuses the id of the "replied" or "finished" note of that
turn, so macOS replaces the banner. In the same diff only the ask note is sent. If the
ask arrives a poll later and `updatedAt` has changed, the ids differ and two banners can show.

## Phone notifications through Bark (2026-10-28)

iOS stops the app in the background and free signing has no push, so the Mac app
forwards each of its notes to the Bark app (`cfind/PhonePush.swift`) at once (the first
version sent only while away; the user wanted it immediate). Away from the Mac (no input
for 2 minutes, or the screen locked), the chat on the Mac screen does not count as read. The text is sealed with AES-GCM (key 16/24/32
characters; Bark settings AES256, GCM, noPadding), with a fresh 12-character IV per push
in the `iv` field, which overrides the IV saved in Bark (Bark's CiphertextProcessor). The
POST body has only `ciphertext` (ciphertext then the 16-byte tag, base64, as CryptoSwift's
GCM combined mode wants) and `iv`. A tap opens `cfind://open?agent=ID` or
`?session=PATH`; the iPhone app shows that chat in the Agents tab. Setup: cfind > Settings
(⌘,) on the Mac, with the Bark URL, the key and Send test.

| case | result |
| --- | --- |
| link round trip: agent id; session path with spaces, `&`, `?`, `+`, `#`, non-ASCII | Pass (unit) |
| pairing links still pair; `cfind://open` without a value or with another name is not a chat | Pass (unit) |
| request: POST, form body with only `ciphertext` and `iv`, no raw `+`; CryptoKit opens it to title, body, url, group | Pass (unit, macOS) |
| bad URL, key not 16/24/32 ASCII characters: error | Pass (unit, macOS) |
| 100 IVs all different, 12 ASCII characters | Pass (unit, macOS) |
| the real `PhonePush.post` against a fake Bark server in node: node's own `aes-256-gcm` decrypts it; a 400 answer, a closed port and a bad key give the status text | Pass (swiftc CLI from the app sources) |
| UI: `testOpenLinkShowsChat` on the harness: after pairing, `open(cfind://open?agent=ID)` relaunches the app (cold start) and shows that chat in the Agents tab | Pass |

Unit tests: 46 on iOS, 33 on macOS. The UI test clears `-cfind-reset` before
`open(_:)`, because `open` launches the app again with its arguments. Not tested here:
a real push through Bark's server to a phone (needs the user's Bark key), and the away
check (system state).

## Markdown tables in chat (2026-10-28)

Before, a table showed as raw `| a | b |` lines. Now `Markdown.blocks` returns
`.table(head, rows)` for a line with `|` followed by a divider line (`|---|:--:|`, same
regex as the web page). Rows go on while lines have `|` and are not blank. Inside
fenced code a table stays code. `TableBlock` shows a `Grid`: header semibold, a divider
between rows, inline Markdown in cells, each column as wide as its text up to 180 pt
(the `UpTo` layout; a frame can't wrap text inside a sideways ScrollView). A table that
fits keeps its own width; a wider one scrolls sideways (`ViewThatFits`). Column `:`
alignment is not used.

- `MarkdownTests.testTables`: header/rows, ragged rows, inline Markdown kept for the
  view, divider without pipes, no divider = text, single `-` divider = text, fenced code.
- Visual check (temporary test, not kept): a `Bubble` with a 7-column table and a 2x2
  table in a 393 pt window on the iPhone 17 Pro simulator, light and dark, drawn with
  `drawHierarchy` (the window needs the app's `UIWindowScene`, or it draws blank).
  Wide table: columns wrap at 180 pt and scroll; at offset 400 the last columns show.
  2x2 table: box hugs the table. Pass.
- iOS unit tests 47/47, Mac build OK.

## Background command after the turn (2026-10-29)

- The daemon now sends a session whose turn ended while a background command runs as
  `idle` with `shell: true` (it was `running`). Lists show Idle without an app update.
- The chat adds a note "Done · a background command is still running" (`Session.shell`,
  `ChatView.items`). Needs the app reinstalled.
- iOS unit tests 47/47, Mac build passes. Not checked on the phone.

## Known limits

- The first metrics event is the whole snapshot (about 500 KB); after that only
  changes are sent.
- Pairing over plain `http://` only works on the simulator (`NSAllowsLocalNetworking`).
  A phone needs the Tailscale HTTPS address.

## Test leftovers

None. The simulator device was revoked and the test agent card removed.

## Rerun before you change this area

1. `npm test` in `ts` (devices and contract tests), in the context-find repo.
2. `cfindTests` on iOS and macOS (command above).
3. Build for testing, make a code, run the UI test with the three env vars.
4. Revoke the simulator device (Connections) and remove the test agent card.
