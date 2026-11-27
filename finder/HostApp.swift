import Cocoa

/// Host app for the Finder extension.
///
/// Launched as `MergeFolders --merge PATH...`, it shows what will merge, asks
/// for a destination, and runs the bundled `mergefolders` script. Launched
/// without arguments it explains how to turn the Finder extension on.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var sources: [URL] = []
    private var destination: URL?

    private var destLabel: NSTextField!
    private var chooseButton: NSButton!
    private let selectionText = NSTextView()
    private var previewButton: NSButton!
    private var mergeButton: NSButton!
    private var statusLabel: NSTextField!
    private var spinner: NSProgressIndicator!

    private static let logURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MergeFolders.log")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if sources.isEmpty { sources = Self.parseSources() }
        buildMenu()
        showWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, urls.count == 1,
              let request = URLComponents(url: url, resolvingAgainstBaseURL: false),
              request.scheme == "mergefolders", request.host == "select",
              let items = request.queryItems, !items.isEmpty else { return }
        let paths = items.compactMap { item -> String? in
            guard item.name == "path", let path = item.value, path.hasPrefix("/"),
                  !path.utf8.contains(0) else { return nil }
            return path
        }
        guard paths.count == items.count, window == nil || sources.isEmpty else { return }
        sources = paths.map { URL(fileURLWithPath: $0) }
        if window != nil {
            window.orderOut(nil)
            destination = nil
            showWindow()
        }
    }

    private func showWindow() {
        if sources.isEmpty {
            buildWelcomeWindow()
        } else {
            buildMergeWindow()
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        if !sources.isEmpty { Self.appendLog("Opened merge window for \(sources.count) selected items.\n") }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private static func parseSources() -> [URL] {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--merge") else { return [] }
        return args[(i + 1)...].map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Windows

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Merge Folders",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func buildWelcomeWindow() {
        window = makeWindow(title: "Merge Folders", height: 250)

        let title = NSTextField(labelWithString: "Merge Folders is installed")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        add(title, frame: NSRect(x: 20, y: 200, width: 460, height: 22))

        let body = NSTextField(wrappingLabelWithString: """
            In Finder, select two or more folders (or files), right-click, and choose \
            “Merge Folders…”. Their contents move into one folder you pick, and \
            name clashes become “name (2).ext” — nothing is overwritten.

            If the item is missing, turn on “Merge Folders” under Finder Extensions.
            """)
        add(body, frame: NSRect(x: 20, y: 100, width: 460, height: 90))

        let button = NSButton(title: "Open Finder Extensions…", target: self, action: #selector(openExtensions))
        button.bezelStyle = .rounded
        add(button, frame: NSRect(x: 20, y: 40, width: 200, height: 32))
    }

    private func buildMergeWindow() {
        window = makeWindow(title: "Merge Folders — \(sources.count) selected", height: 430)

        let count = sources.count
        let header = NSTextField(labelWithString: "Merge \(count) selected item\(count == 1 ? "" : "s") into:")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        add(header, frame: NSRect(x: 20, y: 390, width: 460, height: 20))

        destLabel = NSTextField(labelWithString: "No destination chosen")
        destLabel.textColor = .secondaryLabelColor
        destLabel.lineBreakMode = .byTruncatingMiddle
        add(destLabel!, frame: NSRect(x: 20, y: 358, width: 340, height: 20))

        chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseDestination))
        chooseButton.bezelStyle = .rounded
        add(chooseButton!, frame: NSRect(x: 370, y: 352, width: 110, height: 30))

        let scroll = NSScrollView()
        add(scroll, frame: NSRect(x: 20, y: 190, width: 460, height: 150))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = selectionText
        text.frame = scroll.bounds
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.isEditable = false
        text.drawsBackground = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = sources.map(\.path).joined(separator: "\n")
        scroll.documentView = text

        statusLabel = NSTextField(wrappingLabelWithString: "Preview the planned moves or merge now. Files with matching names are kept with a numbered suffix.")
        statusLabel.textColor = .secondaryLabelColor
        add(statusLabel, frame: NSRect(x: 20, y: 145, width: 460, height: 36))

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        add(spinner, frame: NSRect(x: 20, y: 20, width: 20, height: 20))

        previewButton = NSButton(title: "Preview", target: self, action: #selector(preview))
        previewButton.bezelStyle = .rounded
        previewButton.isEnabled = false
        add(previewButton, frame: NSRect(x: 255, y: 14, width: 110, height: 32))

        mergeButton = NSButton(title: "Merge", target: self, action: #selector(merge))
        mergeButton.bezelStyle = .rounded
        previewButton.keyEquivalent = "\r"
        mergeButton.isEnabled = false
        add(mergeButton, frame: NSRect(x: 370, y: 14, width: 110, height: 32))
    }

    private func makeWindow(title: String, height: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }

    private func add(_ view: NSView, frame: NSRect) {
        view.frame = frame
        window.contentView?.addSubview(view)
    }

    // MARK: - Actions

    @objc private func openExtensions() {
        let pane = "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync"
        if let url = URL(string: pane), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @objc private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Merge Here"
        panel.message = "Merge into which folder?"
        panel.directoryURL = sources.first?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        destination = url
        selectionText.string = sources.map(\.path).joined(separator: "\n")
        statusLabel.stringValue = "Preview the planned moves or merge now."
        statusLabel.textColor = .secondaryLabelColor
        previewButton.isEnabled = true
        destLabel.stringValue = url.path
        destLabel.textColor = .labelColor
        mergeButton.isEnabled = true
    }

    @objc private func openDestination() {
        if let destination { NSWorkspace.shared.open(destination) }
    }

    @objc private func closeWindow() { window.close() }

    @objc private func preview() { runMerge(preview: true) }

    @objc private func merge() { runMerge(preview: false) }

    private func runMerge(preview: Bool) {
        guard let destination, !sources.isEmpty else { return }
        guard let script = Bundle.main.url(forResource: "mergefolders", withExtension: nil) else {
            statusLabel.stringValue = "This copy of Merge Folders is damaged: the mergefolders script is missing."
            return
        }

        mergeButton.isEnabled = false
        previewButton.isEnabled = false
        chooseButton.isEnabled = false
        spinner.startAnimation(nil)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = preview ? "Preparing preview…" : "Merging…"

        let arguments = (preview ? ["--dry-run"] : []) + ["--to", destination.path] + sources.map(\.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = script
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            let output: String
            let failed: Bool
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                failed = process.terminationStatus != 0
                output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                failed = true
                output = "Could not start the merge: \(error.localizedDescription)"
            }

            if !preview {
                Self.appendLog("$ mergefolders \(arguments.joined(separator: " "))\n\(output)\n")
            }

            DispatchQueue.main.async {
                self.spinner.stopAnimation(nil)
                if !preview && !failed {
                    self.chooseButton.title = "Open Folder"
                    self.chooseButton.action = #selector(self.openDestination)
                    // The merge is finished: the only remaining step is closing.
                    self.mergeButton.title = "Done"
                    self.mergeButton.action = #selector(self.closeWindow)
                    self.previewButton.keyEquivalent = ""
                    self.mergeButton.keyEquivalent = "\r"
                }
                self.chooseButton.isEnabled = true
                self.previewButton.isEnabled = preview || failed
                self.mergeButton.isEnabled = true
                self.selectionText.string = output
                self.selectionText.scrollToBeginningOfDocument(nil)
                self.statusLabel.textColor = failed ? .systemRed : .labelColor
                self.statusLabel.stringValue = output.isEmpty
                    ? (failed ? "The merge failed." : "Done.")
                    : (output.components(separatedBy: "\n").last ?? output)
            }
        }
    }

    private static func appendLog(_ text: String) {
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: logURL) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let size = attrs[.size] as? NSNumber, size.intValue > 262_144 {
                try? handle.close()
                try? text.write(to: logURL, atomically: true, encoding: .utf8)
                return
            }
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
