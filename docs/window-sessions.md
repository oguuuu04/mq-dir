# Browser window sessions

Before Phase 2, every browser window read the shared active project ID and
wrote its pane snapshots back to the same project record. The last window
to save could replace another window's tabs.

A typed SwiftUI WindowGroup now carries a UUID per browser window. Its root
uses that UUID to select a session from the shared WorkspaceManager. Each
session has a selected project plus a snapshot for each visited project.
Project switches save the outgoing panes before replacing the child view.
Project names, order, Favorites, preferences, file work and Undo are shared.

All mutations enter the main-actor WorkspaceManager. It debounces the
combined state and sends it to one FIFO writer. Each open browser refreshes
its snapshot on quit and flushes through that writer. Explicit AppKit window
close removes the session and immediately flushes it, while app quit keeps
the open sessions. The first browser scene asks SwiftUI to open the other
saved UUIDs. SwiftUI can match an already restored window to the same UUID.
Window positions and stacking remain under macOS control.

## On-disk format

A previous file contains `projects[].state` and `activeProjectID`. The
first browser window takes a copy of all those layouts and keeps the active
project. The original file is backed up as `state.before-window-sessions.json`
before the first write. An upgrade that cannot back up the old file keeps
the original and shows an error.

The new file retains the shared keys and adds a `windowSessions` array:

```json
{
  "windowSessions": [
    {
      "id": "FA3863EF-7037-4972-B377-93AB40B294E0",
      "projectID": "D700369B-5B68-46E1-A094-A42A0129E04A",
      "snapshots": {
        "D700369B-5B68-46E1-A094-A42A0129E04A": { "layout": 1, "focusedPaneIndex": 0 }
      }
    }
  ]
}
```

The snapshot above is abbreviated. Each live snapshot contains the existing
pane and tab records. An empty array records that all windows were explicitly
closed. A malformed window or snapshot record is isolated and the original is
backed up by the existing corruption recovery. Missing project references
fall back to a valid project. Window sizes and positions, interrupted launches,
and app relaunch with macOS restoration disabled may differ by OS version.
