import AppKit
import SwiftUI

private struct BrowserWindowCommandsKey: FocusedValueKey {
    typealias Value = BrowserWindowCommands
}

extension FocusedValues {
    var browserWindowCommands: BrowserWindowCommands? {
        get { self[BrowserWindowCommandsKey.self] }
        set { self[BrowserWindowCommandsKey.self] = newValue }
    }
}

struct MenuCommands: Commands {
    @FocusedValue(\.browserWindowCommands) private var windowCommands
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var fileWork = FileWorkCenter.shared
    @ObservedObject var workspace: WorkspaceManager

    /// Resolved binding for a customisable action — user override
    /// from `WorkspaceSettings`, falling back to the default. Used
    /// by every menu item whose shortcut is exposed in Settings →
    /// Shortcuts so the menu re-attaches when the user remaps.
    private func binding(_ action: ShortcutAction) -> ShortcutBinding {
        workspace.workspace.settings.binding(for: action)
    }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if let editor = Self.textEditor {
                    editor.undoManager?.undo()
                } else if let job = fileWork.lastUndoableJob {
                    fileWork.undo(job)
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            Button("Redo text editing") {
                if let editor = Self.textEditor {
                    editor.undoManager?.redo()
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "browser") }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Tab") { post(.newTab) }
                .keyboardShortcut(binding(.newTab))
            Divider()
            Button("Open Folder...") { post(.openFolder) }
                .keyboardShortcut(binding(.openFolder))
            Button("Open Selected") { post(.openSelected) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Open Selected (Alternate)") {
                dispatch(text: #selector(NSResponder.moveToEndOfDocument(_:)), file: .openSelected)
            }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("New Folder") { post(.newFolder) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Close Tab") { post(.closeTab) }
                .keyboardShortcut(binding(.closeTab))
            Button("Reopen Closed Tab") { post(.reopenClosedTab) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            Button("Reveal in Finder") { post(.revealSelected) }
                .keyboardShortcut(binding(.revealInFinder))
            Divider()
            Button("Add to Favorites") { post(.addCurrentFolderToFavorites) }
                .keyboardShortcut(binding(.addToFavorites))
        }

        // Replace the system pasteboard group entirely so file-level
        // Copy/Paste/Delete and Select All actually run on the focused
        // pane's selection. Each item routes to a `mqdir*` notification
        // when the first responder isn't a text view; if a TextField
        // (search box, inline rename) IS the first responder we
        // forward to its native AppKit action so the user's expected
        // text-Cmd+C / Cmd+V / Cmd+A still works there.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { dispatch(text: #selector(NSText.cut(_:)), file: nil) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { dispatch(text: #selector(NSText.copy(_:)), file: .copy) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { dispatch(text: #selector(NSText.paste(_:)), file: .paste) }
                .keyboardShortcut("v", modifiers: .command)
            Button("Move Items Here") { post(.movePasteboardItems) }
                .keyboardShortcut("v", modifiers: [.command, .option])
            // ⌘⌫ matches Finder's "Move to Trash". The dispatch helper
            // forwards plain Delete (text-edit selector) when a TextField
            // is the first responder, but ⌘⌫ in a TextField is rare on
            // macOS and harmlessly invokes NSText.delete(_:) on a
            // selected range.
            Button("Move to Trash") { dispatch(text: #selector(NSText.delete(_:)), file: .delete) }
                .keyboardShortcut(binding(.moveToTrash))
            // Permanent delete bypasses the trash — confirmed via
            // NSAlert in the focused pane's view model.
            Button("Delete Immediately\u{2026}") { post(.permanentDelete) }
                .keyboardShortcut(binding(.deleteImmediately))
            Divider()
            Button("Select All") { dispatch(text: #selector(NSText.selectAll(_:)), file: .selectAll) }
                .keyboardShortcut("a", modifiers: .command)
        }

        // File-selection actions tucked into the Edit menu just below
        // the pasteboard group. Eagle / Finder parity for the shortcuts
        // power users hit reflexively.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Open with Default App") { post(.openWithDefaultApp) }
                .keyboardShortcut(binding(.openWithDefaultApp))
            Button("Duplicate") { post(.duplicate) }
                .keyboardShortcut(binding(.duplicate))
            Divider()
            Button("Copy File Path") { post(.copyFilePaths) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Copy Folder Path") { post(.copyFolderPath) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            Button("Copy Name") { post(.copyName) }
            Divider()
            let rename = binding(.rename)
            // Bare Return belongs to the list so the inline field can submit it.
            Button(rename == ShortcutAction.rename.defaultBinding ? "Rename (Return)" : "Rename") {
                post(.rename)
            }
            .keyboardShortcut(rename == ShortcutAction.rename.defaultBinding ? nil : rename.keyboardShortcut)
        }

        CommandGroup(after: .textEditing) {
            Button("Find") { post(.focusSearch) }
                .keyboardShortcut(binding(.find))
            Button("Show Preview") { post(.togglePreview) }
                .keyboardShortcut(binding(.togglePreview))
        }

        CommandGroup(after: .toolbar) {
            Button("Back") { post(.goBack) }
                .keyboardShortcut(binding(.back))
            Button("Forward") { post(.goForward) }
                .keyboardShortcut(binding(.forward))
            Button("Reload") { post(.reload) }
                .keyboardShortcut(binding(.reload))
            Button("Parent Folder") { dispatch(text: #selector(NSResponder.moveToBeginningOfDocument(_:)), file: .parentFolder) }
                .keyboardShortcut(binding(.parentFolder))
            Button("Toggle Hidden Files") { post(.toggleHiddenFiles) }
                .keyboardShortcut(binding(.toggleHiddenFiles))
            Divider()
            // As List / As Tree intentionally have no keyboard shortcut:
            // ⌥⌘1–4 are claimed by Window → Focus Pane and view-mode
            // toggling is rare enough to live on the menu and the
            // toolbar's segmented control.
            Button("As List") { post(.setViewModeList) }
            Button("As Tree") { post(.setViewModeTree) }
        }

        // Tab navigation lives under the standard Window menu, matching
        // Safari/Finder where ⌘⇧[ ⌘⇧] move between tabs and ⌘1…⌘9 jump
        // to a specific one. We attach `after: .windowArrangement` so it
        // appears below the system "Bring All to Front" entry.
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Next Tab") { post(.nextTab) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Show Previous Tab") { post(.previousTab) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            selectTabButton(index: 0, key: "1")
            selectTabButton(index: 1, key: "2")
            selectTabButton(index: 2, key: "3")
            selectTabButton(index: 3, key: "4")
            selectTabButton(index: 4, key: "5")
            selectTabButton(index: 5, key: "6")
            selectTabButton(index: 6, key: "7")
            selectTabButton(index: 7, key: "8")
            selectTabButton(index: 8, key: "9")
            Divider()
            // ⌥⌘1–4 move keyboard focus between the four panes in the
            // current layout. Indices outside the active layout's pane
            // count are silently dropped by MainWindowView.
            focusPaneButton(index: 0, key: "1")
            focusPaneButton(index: 1, key: "2")
            focusPaneButton(index: 2, key: "3")
            focusPaneButton(index: 3, key: "4")
        }

        CommandGroup(replacing: .help) {
            Link("File Manager on GitHub",
                 destination: URL(string: "https://github.com/oguuuu04/mq-dir")!)
        }
    }

    private func selectTabButton(index: Int, key: KeyEquivalent) -> some View {
        Button("Select Tab \(index + 1)") {
            post(.selectTab(index: index))
        }
        .keyboardShortcut(key, modifiers: .command)
    }

    private func focusPaneButton(index: Int, key: KeyEquivalent) -> some View {
        Button("Focus Pane \(index + 1)") {
            post(.focusPane(index: index))
        }
        .keyboardShortcut(key, modifiers: [.command, .option])
    }



    private func post(_ command: AppCommand) {
        guard Self.textEditor == nil, !(NSApp.keyWindow?.firstResponder is KeyCaptureNSView) else { return }
        windowCommands?.send(command)
    }

    // Quick Look can install a read-only NSTextView as first responder.
    // Only editable text views and field editors own text commands.
    private static var textEditor: NSTextView? {
        guard let view = NSApp.keyWindow?.firstResponder as? NSTextView,
              view.isFieldEditor || view.isEditable else { return nil }
        return view
    }

    private func dispatch(text selector: Selector, file command: AppCommand?) {
        if let editor = Self.textEditor {
            NSApp.sendAction(selector, to: editor, from: nil)
        } else if let command {
            post(command)
        }
    }
}
