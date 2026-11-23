# File Manager

File Manager is a macOS file manager forked from [h5nam/mq-dir](https://github.com/h5nam/mq-dir). See [LICENSE](LICENSE) for the upstream copyright and MIT license.

![Launch demo of upstream mq-dir](.github/assets/launch.gif)

## Why

A modern coding session is half source, half artifacts: generated images, recorded demos, PDFs, screenshots from QA, exported transcripts, downloaded models, design specs. None of it lives where your code does — and Finder wasn't built for that volume or for the way agents now produce work in parallel.

mq-dir gives you up to four independent panes side by side. One per project, one per agent, one for the artifact dump. Each pane keeps its own folder, sort, scroll position, and column widths — and remembers them across launches and force-quits.

## Features

- 🟦 **1 / 2H / 2V / 4-pane layouts** — focused-pane routing, independent folder per pane.
- ↹ **Per-pane tabs** — Safari-style strip with X/+, ⌘T / ⌘W / ⌘⇧T / ⌘1…⌘9 / ⌘⇧[ / ⌘⇧], drag to reorder or move within a window, drag a tab onto Favorites to bookmark its folder, right-click Close Other / Close to Right / Duplicate, last-tab safety placeholder. To drag a folder to another app, use its row in the file list or tree.
- 🌳 **VS Code-style tree view** — per-tab toggle, lazy child loading, separate chevron hit target (clicking a folder name selects without expanding), Shift / Cmd multi-select, file drag-out to external apps. New tabs via **⌘+double-click** or **⌘+Enter** on a folder (same as list view).
- ⌨️ **Keyboard nav + Finder-parity right-click** — ↑/↓ step through rows (hold to repeat, Shift to extend the selection); **Return** renames one selected item. **⌘↓ / ⌘O** opens the selection, **⌘↑** goes to the parent folder, **⌘⇧N** creates a folder, and **⌘Return** opens a selected folder in a new tab. Use **⌘C → ⌘V** to copy files or **⌘C → ⌘⌥V** to move them. **⌘X** cuts text in editing fields. Row context menu covers Open With ▸ (LaunchServices candidates + Other…), Get Info, Reveal in Finder, Copy / Copy Path, Duplicate, Rename, **Normalize Filename to NFC** (rewrites Hangul filenames stored as decomposed NFD on disk to the precomposed NFC form Windows / Slack / Discord / Gmail / web uploaders expect — multi-select supported, no-op on already-NFC names), and Move to Trash. Multi-selection right-clicks act on the whole selection. Restoring keyboard focus after a rename is handled correctly in both list and tree view.
- ⚙️ **Settings → Shortcuts** — 17 actions re-bindable from Preferences (⌘,), including F1…F12. Reset-to-default per row.
- 👀 **Per-tab preview pane** — toggle in the pane header (or ⌘⇧P). PDFs render through PDFKit with continuous scroll + paging; everything else routes through Quick Look for images, code, video, audio, office docs (DOCX/PPTX/XLSX). MarkdownUI handles `.md` with full GFM (tables, code blocks, lists). Folder/multi/empty selections get custom summaries. Zip archives preview in-pane (listing + single-entry decode). Multi-page navigation for non-PDF documents and formats macOS Quick Look has no generator for (HWP, etc.) is best done with ⎵ to summon the floating Quick Look panel, or ⇧↩ to open in the system default app (e.g. Hancom Office Viewer for HWP).
- 🏷️ **Finder tag display** — per-tag colour swatches (red / orange / yellow / green / blue / purple / grey) read straight from macOS metadata, including multi-tag rows. Sidebar Tags section lists every tag in the current folder. Read-only — applying or editing tags happens in Finder.
- 📂 **Custom folder icons** — folders with a Finder-assigned custom icon (Get Info → drag image) render that icon in the row, not the system default.
- ⭐ **User-editable Favorites sidebar** — drag folders in (or drag a tab in to bookmark its folder), right-click Remove or Rename, drag to reorder, ⌘⇧D adds the focused pane's folder. Real Finder folder icons, stale-path styling.
- 📁 **Projects (workspaces)** — named snapshots of (layout + pane tabs + focus). + button creates one, click switches, right-click Rename / Delete, drag to reorder. Switching auto-saves the outgoing project.
- 💾 **State persistence** — every pane / tab / favorite / project survives relaunch, force-quit, and even schema upgrades (legacy `state.json` shapes auto-migrate).
- 🔎 **Per-pane recursive search** — debounced, case-insensitive substring match across the current folder's subtree. ⌘F.
- 🔗 **Selectable coding app integrations** — choose cmux, Orca, Paseo, Claude Code Desktop, or Codex Desktop in the sidebar, then Sync to list local workspace folders. Click to open a folder; ⌘-click opens a new tab. The selection survives relaunch. See [setup and support boundaries](docs/integrations.md).
- 🎨 **Native macOS look** — SwiftUI + AppKit, system theme tokens, hand-finished app icon.

**Roadmap**

- 3-pane layout option.
- More archive formats in-pane (tar / 7z / rar).
- Open to ideas — [file an issue](https://github.com/oguuuu04/mq-dir/issues).

## Build and test

Use macOS 14 or later, Xcode 16.2 or later, and XcodeGen. The Xcode project is generated from `project.yml`; `Scripts/generate-project.sh` copies the reviewed Swift package pins into the generated workspace.

```bash
brew install xcodegen
git clone https://github.com/oguuuu04/mq-dir.git
cd mq-dir
swift test
Scripts/generate-project.sh
xcodebuild -project mq-dir.xcodeproj -onlyUsePackageVersionsFromResolvedFile \
  -scheme mq-dir -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Local CODE_SIGNING_ALLOWED=NO test
```

The Xcode test action builds the app and runs the macOS service tests. In Xcode, open `mq-dir.xcodeproj` and run the `mq-dir` scheme to launch **File Manager**. To run a Debug smoke test with disposable state, set `MQDIR_TEST_STATE_DIR` to a newly created temporary directory in the scheme's Run environment. Use dummy files in that directory for file-operation checks.

## Local state and distribution

File Manager uses bundle ID `com.oguuuu04.filemanager` and stores state in `~/Library/Application Support/com.oguuuu04.filemanager/state.json` in the default unsandboxed configuration. It starts with its own state and macOS preferences. The original mq-dir state directory is outside the fork's persistence path.

Local Debug builds use unsigned development settings. The separate Sandboxed configuration retains its existing entitlements and requires a suitable signing team for distribution. Phase 0 is distributed as source. The inherited cask, appcast and release scripts describe the upstream app. Fork builds ship without Sparkle or a Discord feedback client, and the inherited release and nightly jobs are gated to upstream. Use **Report an Issue** in the sidebar to open the fork's issue tracker.

## Privacy

External images in Markdown previews are blocked by default. Choosing **Load external images** sends requests to the image servers for that document. Opening another document resets this permission.

## Out of scope for v1

Cloud sync, file editing, plugins, iPadOS/iOS port, localization beyond English. Archive *editing* (we preview zip in-pane; tar / 7z / rar previews are on the roadmap, not write support).

## Contributing

PRs welcome. This fork accepts contributions under the [MIT license](LICENSE) and makes DCO sign-off optional. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow, [SECURITY.md](SECURITY.md) for vulnerability disclosure, and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
