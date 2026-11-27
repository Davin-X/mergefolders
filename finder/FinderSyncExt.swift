import Cocoa
import FinderSync

/// Finder Sync extension: adds "Merge Folders…" to the top-level context menu
/// and hands the selection to the host app, which does the actual work.
@objc(FinderSync)
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Monitor the whole disk so the item shows up in every Finder window.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        let menu = NSMenu(title: "")
        let item = NSMenuItem(
            title: "Merge Folders…",
            action: #selector(mergeFolders(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(systemSymbolName: "arrow.triangle.merge", accessibilityDescription: nil)
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func mergeFolders(_ sender: AnyObject?) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !urls.isEmpty else { return }

        // MergeFolders.app sits three levels above this .appex:
        // MergeFolders.app/Contents/PlugIns/MergeFoldersExt.appex
        let app = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard app.pathExtension == "app" else { return }

        // The extension is sandboxed, so hand off through LaunchServices
        // instead of spawning a process. A new instance per invocation keeps
        // two merges independent.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--merge"] + urls.map(\.path)
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }
}
