DONE
# Call lane (11-13, PL Call window lead) - what was built

Commits: pl-call `c432339`; pl-call-ios `2703b19` (pushed to main). Nothing published to the SideStore feed (latest release is still build-54), the running serve.py and channel were not restarted, no vault edit, no session number claimed.

## What was built
1. **STATUS chip** (first chip, then WHAT'S LEFT, then the config's own chips). One tap: the PC answers at once from real state, `GET /status` (status.py: live sessions from `~/.claude/pl-session-bus.json`, newest release + last Actions run of pl-dev-ios and pl-call-ios via gh, open QUEUE count and the next item from NEXT SESSION), shown and spoken; the session is also asked in two short sentences. Works while the session is busy.
2. **WHAT'S LEFT chip**: `GET /left`, the open QUEUE items (not DONE, not struck), top 5 spoken, the rest counted.
3. **Pictures on the call**: the `reply` tool has an optional `image` (full local path, PNG/JPEG, under 12 MB). serve.py COPIES it to `~/.config/pl-call/out/<random>.png` (the phone can never ask for an arbitrary file), event carries `image: "img/<name>"`, `GET /img/<name>` is keyed. Psyclaupse shows it in the conversation, tap = full screen with pinch zoom, drag, double tap, X. A bad path or non-picture: the words still go out and Claude is told "the picture was not shown: ..." so it can fix the path. Instructions in channel.py tell Claude when to use it.
4. **Stale approvals clear themselves**. Anthropic's Channels reference (code.claude.com/docs/en/channels-reference, Relay permission prompts) says: when the terminal answers first, the pending remote request is dropped, and there is **no cancel signal to the server**. So: a card is cleared when the session moves on (its next `reply`, or a newer permission request) or after a time limit (10 min for tool approvals, 30 min for auto-mode blocks). serve.py emits `permission_answered` with `expired: true`; Psyclaupse removes the card, notification, ring and head-gesture reader and writes "That approval was cleared: the session moved on." A late tap on a cleared card is accepted quietly (nothing sent to Claude Code). Honest limit: a card answered in the terminal stays until the next reply, a newer request, or the time limit.
5. **Build announcement**: serve.py polls both repos' newest release every 2 min (first look only records, `~/.config/pl-call/last-builds.json`); a new tag becomes an `announce` event: shown as a system line, spoken when the call is quiet (not mid-sentence, no ask open, Claude not mid-turn), a notification when the app is not in front.
6. **One-tap stop**: a round stop button appears beside the audio button while Claude is speaking; it silences the voice and anything queued (same as his spoken "stop"). It does not stop Claude's work (Channels has no interrupt).
7. Build workflow got a `publish` input (default on) so compile checks do not put a release on the feed.
Audio untouched (no `.bluetoothHighQualityRecording`).

## How each was tested
- `python status.py --selftest` ok (queue parser, bus filter, time words, live gh read).
- `python channel.py --selftest` ok; `py_compile` of serve.py, channel.py, status.py ok.
- `serve.call_selftest()` ok: expiry by reply, by a newer request, by timeout; late verdict swallowed; announce; picture hosting by copy; non-picture refused with the words kept.
- Live HTTP test on a scratch port 8899 (his :8791 untouched), real key: no key = 401 on /status and /img; /status and /left = 200 with real text; /ch/reply with a real PNG -> event image -> GET /img = 200 image/png with PNG bytes; `..` and bad names = 404; reply with C:\Windows\win.ini = warning, words delivered; perm then reply -> `permission_answered expired:true`.
- Psyclaupse: build workflow run 43557150122 (publish off) = success, 1m52s; logic workflow run 43557144432 (PLCallCore tests incl. the new event decode and cleared-approval tests, hygiene scan) = success.

## What needs his phone (and a restart of his running programs)
- **Restart serve.py and the call window's channel** (the running copies still have the old code; /status, /left, /img, expiry and the announcer only exist after the restart).
- Install the next published build (this one was not published); then: tap STATUS and WHAT'S LEFT in a call; ask Claude to send a screenshot (reply with image) and tap it; answer an approval in the terminal then watch the phone card clear on the next reply; the stop button while Claude talks; the announcement when a build lands.
- Untested on a device: the full-screen pinch/drag feel, the stop button placement with a long chip row, the spoken status length.
- Not done: the stop button is not on the Lock Screen Live Activity or the watch; Channels has no way to interrupt Claude's work from the phone.
