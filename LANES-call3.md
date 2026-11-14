DONE
# Call lane 3 (11-14): answer "is that correct" from the lock screen, and the call reads while it works

Branches: `wave-call3` in both repos, worktrees `C:\dev\pl-call--call3` (commit `47f6fc5`) and `C:\dev\pl-call-ios--call3` (commit `c75bba7`, pushed to origin so the build could run). Nothing published to the SideStore feed, live serve.py on :8791 not restarted, no vault edit, no session number claimed. Not merged to main.

Docs read first: code.claude.com/docs/en/hooks (common input incl. session_id and transcript_path, "the transcript may lag the in-memory conversation"; PostToolUse input; Stop input `last_assistant_message`, which the page says to use for read-aloud hooks instead of the transcript; `async: true` runs a command hook in the background without blocking; exit codes).

## A. Yes / Again from the lock screen (pl-call-ios)
- Live Activity (lock screen, StandBy, expanded Dynamic Island, watch Smart Stack) gets a new content-state field `heard`. While "I heard: ..., right?" is pending it shows the heard text and a Yes / Again row (`HeardYesIntent`, `HeardAgainIntent`, `LiveActivityIntent`s in `Shared/Intents.swift`, `IntentBridge.heard`). The Island expands once with the alert "Did I hear you right?".
- Local notification, category `ask.heard`, actions "Yes" and "No, again" (no unlock needed), posted only when the app is not frontmost. One id, so a new check replaces the old banner.
- First answer wins: `clearHeard()` (answer in app, by voice, Live Activity, notification, or the 25 s timeout) removes the banner and redraws the activity without buttons. A late tap on a stale button is a no-op (`settleHeard` needs a pending check).
- No push; the call's background audio keeps the app alive for the intents.
- Files: `Shared/{CallActivityAttributes,IntentBridge,Intents}.swift`, `PLCall/Engine/{CallModel,NotificationHub,LiveActivityController}.swift`, `PLCallWidgets/CallLiveActivity.swift`.

## B. The call reads while it works (pl-call)
- `narrate.py` (new): Claude Code hook, `PostToolUse` (matcher `*`) and `Stop`, both `async: true`, registered in `call-settings.json`, which only `call-window.cmd` passes, plus an env gate `PLCALL_WINDOW=1` (same as `blocked.py`). It exits unless a call is live (GET `/ch/live`). It reads the hook's `transcript_path`, takes assistant TEXT blocks after a per-session byte cursor (`~/.config/pl-call/narrate-<session>.cursor`; the first run starts at his last message; half-written lines and subagent lines are skipped), turns them into short speakable words (code, paths, hashes, links dropped; max about 380 chars; "From the call:" quote lines skipped) and POSTs each to `/ch/narrate`. At `Stop` it also uses `last_assistant_message` (the transcript may not have it yet), de-duplicated. Never tool output, never thinking.
- `serve.py`: `GET /ch/live`, `POST /ch/narrate` (localhost + call key, like the other /ch paths). It becomes a normal non-final assistant event, so Psyclaupse, the web page and the R1 speak it like a progress line. **Deviation from the brief:** the brief said POST to `/say`, but `/say` only feeds the R1's `/said` poll, and Psyclaupse never reads it, so the phone would have stayed silent. At Stop the line is skipped if a final `reply` already ended the turn. `PLCALL_PORT` env added so a test copy can run on another port.
- `channel.py` INSTRUCTIONS: the session no longer mirrors on-screen text through `reply`; reply is for answers to call messages and pictures; on-screen working text is to be written as short plain sentences. This replaces the 11-13 "mirror every on-screen message" line.
- Official route only: a documented Claude Code hook. No driving of Claude Code from outside, no bridge.

## Proof
- `python narrate.py --selftest` ok (speakable stripping incl. the leftover-punctuation cases, "From the call" skip, cursor reading on a synthetic transcript: thinking, tool_use, tool_result and subagent lines ignored, partial last line left). It caught a real bug (a mangled regex replacement left a control character after a removed hash).
- `serve.py --selftest` ok (new asserts: narrate is non-final; skipped at Stop after a final reply; spoken at Stop on a fresh turn). `channel.py --selftest` ok (new instruction asserts, ASCII).
- Live test on a second serve.py on :8899 (his :8791 untouched), real key, a copy of the tail of a real transcript (400 lines, only my own output printed): `/ch/live` false before a poll, true after; the hook run by hand with a fake hook input posted 7 assistant lines to the call (all words, no tool output), cursor advanced, second run sent nothing new; Stop with a final reply already sent was skipped. Test copy stopped, cursor files removed.
- iOS: `build` workflow on `wave-call3` with publish off = success (run 43580632108, includes "Package .ipa", Publish skipped); `logic` run on the push = success (43580630925); `scripts/scan.sh` clean. Compile only. XCUITest: the repo has none.

## To go live (lead)
1. pl-call: merge `wave-call3` into master (`git -C C:\dev\pl-call merge wave-call3`), since call-window.cmd and channel-mcp.json point at `C:\dev\pl-call`.
2. Restart serve.py (the keeper `keep.ps1` restarts it within about 20 s of killing it) so `/ch/live` and `/ch/narrate` exist. Do this when he is not on a call.
3. Restart the call window (`call-window.cmd`) so it loads the new `call-settings.json` (the hook entries) and the new channel instructions. The settings go in through `--settings`, so no edit to his settings.json.
4. Merge `wave-call3` into pl-call-ios `main` and run the `build` workflow with publish on; install the new build via SideStore. The Live Activity layout and intent buttons need a real device pass.
5. Check the 11-13 memory note "Calls: mirror both ways" against the new instructions (the on-screen to call half is now the hook).

## Left, with reasons
- Not tested on a device: Yes/Again buttons on the lock screen and Island, the notification actions, whether the Island alert expands, and the 25 s window being long enough to answer from a lock screen (left at 25 s as built before).
- Not tested end to end in the real call window: the first real hook firing inside Claude Code (verified the script by hand with a fake hook input, not Claude Code invoking it). First thing to check after step 3: say something and watch `~/.config/pl-call/narrate-*.cursor` appear.
- Narration repeats nothing it already said, but long on-screen paragraphs are cut to about 380 characters; tune `MAX_CHARS` in `narrate.py` if he wants more.
- Watch app (WatchLink) was not given the Yes / Again buttons.
