# Achiever 0.3.5: installation and changes

This is an updated version of the uploaded Achiever addon for WoW 2.4.3, Interface 20400. Version 0.3.3 was reported working in the user's client; 0.3.4 keeps its synchronization and compatibility fixes while making normal loading silent and the added in-game messages English.

## Changes in 0.3.4

- Removed automatic startup, per-stage, periodic progress, and successful-completion chat messages.
- Retained detailed synchronization progress through the manual `/acstatus` command.
- Translated the added status, loading, unsupported-feature, and diagnostic messages into English.
- Removed the `WARN` prefix from core status output; UI event tracing uses the opt-in debug logger instead.
- Kept a single short English notification for the first actual protected-call or synchronization error. Errors are still counted and can be inspected with `/acstatus`.
- Left server-provided achievement names and descriptions unchanged.
- Preserved existing character progress, settings, and the compatible static cache. A cache reset is not required for this update.

Debug mode is opt-in and its existing setting is preserved. If previously enabled, use `/acdebug` once to disable verbose debug output.

## Installation

1. Exit WoW completely.
2. Back up `Interface/AddOns/Achiever` outside the AddOns directory. Also back up the account/character `SavedVariables/Achiever.lua` files and any corresponding `.bak` files under `WTF`.
3. Replace `Interface/AddOns/Achiever` with the `Achiever` directory from this ZIP. Avoid an extra `Achiever/Achiever` nesting level.
4. Keep your SavedVariables files. Do not run `/acreset` just to install this update.
5. Log in and let synchronization finish. Normal loading intentionally produces no chat output.
6. If needed, run `/acstatus` manually. Confirm version `0.3.4`, state `ready`, and ideally `errors=0`.

## Changes in 0.3.5

- Startup pacing shortened: request spacing 3.0s -> 2.0s, quiet window 3.0s -> 2.0s, no-reply quiet window 8.0s -> 4.0s. Requests are still strictly serial and the 6s startup delay is kept, because the serial pacing prevents the world server from being overloaded at login.
- If the first request gets no server reply for 20 seconds, a single chat message is printed explaining the most likely cause (the account lacks GM permission for the `.achievements` commands). The existing 45s timeout is unchanged.
- Timeout errors now distinguish "no server reply at all" from a timeout after partial data.

## Non-GM accounts (server-side requirement)

The addon does not use any server-side API beyond the `.achievements` chat commands: `enableAchiever`, `getCategories`, `getAchievements`, `getCriteria`, `getCharacterCriteria`. On CMaNGOS these are restricted by the security level stored in the `command` table of the world database. If that level is above the player's, the server silently ignores the command for a normal account, and the addon waits until it times out. This cannot be fixed on the addon side.

To support normal accounts, the server administrator should lower the required level of these subcommands to player level, and make sure the server handler returns only the requesting character's own progress (the static category/achievement/criteria data is public). The server-side source is not included in this ZIP, so verify the exact command names and table on your server first.

## Commands

- `/acstatus`: show version, state, incoming/accepted/rejected protocol-message counts, errors, completed steps, current request, record-message counts, timers, and last command.
- `/acdebug`: toggle detailed debug logging.
- `/acreset`: invalidate the static cache and reload the UI. Character achievement progress and settings are retained; use this only when troubleshooting.
- `/ac`: open the achievement window after synchronization.
- `/console scriptErrors 1`: enable client Lua-error dialogs when testing. The addon does not replace WoW's global error handler.

Progress counters describe actual completed steps and received messages, not a fabricated download percentage. Record-message counts include duplicates; they are not guaranteed unique-record counts.

## Earlier fixes retained

- Single runtime instance, without duplicate Lua/XML includes.
- Correct initial wire version `0`; the internal missing-cache sentinel `-1` is never sent to the server.
- Activation uses the synchronized static version rather than an outdated per-character version.
- Sequential requests, quiet-window pacing, timeouts, and zoning-aware processing.
- Static cache validation and replacement of obsolete snapshot rows.
- Empty-field preservation and malformed-message checks.
- Bounded UI work and notification queues.
- Missing-record safeguards, dense criteria indexes, safe chain traversal, and bounded automatic scrolling.
- Correct scrollbar method hooks, category ordering, frame anchors, and isolated dropdown frames.
- Recognition of supported full/split addon payloads and `ACHI#`-prefixed whisper/system messages.

## Limitations

The server implementation and its acknowledgements are not bundled with this addon. Synchronization uses quiet-window heuristics rather than a fully atomic, transaction-acknowledged protocol; `ready` cannot prove receipt of every possible record.

The addon controls its outgoing request pacing and UI work, not the server's packet-send rate. Native client crashes, network failures, or server command-permission problems cannot be fixed by a Lua `pcall`.

Tracking and player comparison were unfinished in the supplied upstream code. Their user entry points return an English unsupported-feature notice rather than calling missing functions. No new tracking or comparison protocol is implemented here.

Safety bounds remain: up to 64 pending UI jobs, 32 pending notification jobs, 256 displayed criteria per achievement, 128 chain-validation steps, and 100 automatic-scroll search iterations. Visual notifications can be dropped during unusually large bursts without dropping the received earned-achievement data.

## Validation

The package includes 30 Lua 5.1 regression tests, including silent successful startup and manual English status output. Validation also checks 17 unique TOC/XML includes, 45 virtual templates, and 138 inline XML Lua handlers.

Run from the extracted ZIP root with Lua 5.1 and Python 3.9 or later:

```sh
lua5.1 tests/run.lua Achiever/
python3 tests/validate.py Achiever/
```

These tests use mocked WoW APIs. They do not replace testing in the actual client, validate the full WoW UI schema, or demonstrate native memory/network stability.

If synchronization fails again, save the complete `/acstatus` output, any Lua stack trace or client crash report, and the server's response to the recorded command. Do not repeatedly reset the cache or replay snapshot requests.
