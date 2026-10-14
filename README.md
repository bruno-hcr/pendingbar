# PendingBar

A macOS menu bar app that holds the tasks waiting on you, sorts them by priority, due date or app,
and reminds you before they are due. Tasks come from three places: the panel itself, a JSON file, or
an MCP client such as Claude Code (an agent can publish a daily sweep of pending work here).

## Install

```bash
./scripts/build-app.sh --install
```

Builds a release, assembles `build/PendingBar.app`, signs it ad hoc, copies it to `~/Applications`,
links `pendingctl` into `~/.local/bin` and launches the app. Requires Xcode (macOS 14+).

Register the MCP server once:

```bash
claude mcp add --scope user pendingbar -- ~/Applications/PendingBar.app/Contents/MacOS/pendingctl mcp
```

## How it fits together

| Piece | Role |
|---|---|
| `PendingKit` | Model, store, sync rules, reminder planner, sorting, MCP handler. Unit tested. |
| `PendingBar` | SwiftUI `MenuBarExtra` app. Watches the store and reloads on change. |
| `pendingctl` | CLI and stdio MCP server, shipped inside the app bundle. |

The store is `~/Library/Application Support/PendingBar/tasks.json` (override with `PENDINGBAR_HOME`).
Every writer takes an exclusive `flock` and writes atomically, so the app, the CLI and the MCP
server can write at the same time.

## Sync rules

A sync payload:

```json
{
  "origin": "daily-sweep",
  "mode": "snapshot",
  "checkedSources": ["slack", "gmail", "linear"],
  "tasks": [
    {"id": "linear:ENG-123", "title": "Finish ENG-123", "source": "linear",
     "priority": "high", "dueAt": "2026-10-15", "url": "https://example.com/ENG-123"}
  ]
}
```

- `id` is the stable key; the same id updates the same task.
- `mode: snapshot` resolves this origin's open tasks that are missing from the payload, but only for
  sources listed in `checkedSources` (all sources when it is omitted). `merge` only adds and updates.
- A task you mark done stays done even if a later sync sends it again. A task resolved upstream
  reopens if it comes back.
- Manual tasks (origin `manual`) are never touched by a sync.
- `dueAt` accepts ISO 8601, a date (18:00 local), or a relative value (`2h`, `30m`, `3d`).
- Completed tasks are pruned after 14 days.

## Reminders

Configurable in Settings: 48 h, 24 h, 1 h, 20 min, 10 min and 5 min before, plus at the due time.
macOS keeps a limited number of scheduled notifications per app, so PendingBar schedules the 60
nearest and re-plans on every change, every 30 minutes and on wake. Notifications carry Open,
Mark done and Snooze 1 hour actions.

## CLI

```
pendingctl sync payload.json      # or: ... | pendingctl sync -
pendingctl list [--all] [--json]
pendingctl add "Title" --due 2h --priority high --url https://...
pendingctl done <id> | reopen <id> | snooze <id> 1h
pendingctl mcp                    # stdio MCP server: pending_sync, pending_list, pending_add, pending_complete, pending_snooze
```

## Development

```bash
xcrun swift test
PENDINGBAR_SNAPSHOT=/tmp/pb build/PendingBar.app/Contents/MacOS/PendingBar   # renders the list to PNGs
```

## Icon

`scripts/make-icon.swift` draws the icon and writes `Resources/Assets.xcassets/AppIcon.appiconset`;
the build compiles it with `actool` into `Assets.car` + `AppIcon.icns`. macOS caches the notification
icon per bundle id and `CFBundleVersion`, so the build stamps a new `CFBundleVersion` every time. If
notifications still show a blank icon after an icon change, remove PendingBar under System Settings >
Notifications and reopen the app.
