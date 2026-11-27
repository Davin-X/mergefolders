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
    private var mergeButton: NSButton!
    private var statusLabel: NSTextField!
    private var spinner: NSProgressIndicator!

    private static let logURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MergeFolders.log")

    func applicationDidFinishLaunching(_ notification: Notification) {
        sources = Self.parseSources()
        buildMenu()
        if sources.isEmpty {
            buildWelcomeWindow()
        } else {
            buildMergeWindow()
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
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
        window = makeWindow(title: "Merge Folders", height: 430)

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
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.drawsBackground = false
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = sources.map(\.path).joined(separator: "\n")
        scroll.documentView = text

        statusLabel = NSTextField(wrappingLabelWithString: "Files are moved, never copied. Name clashes are kept as “name (2).ext”.")
        statusLabel.textColor = .secondaryLabelColor
        add(statusLabel, frame: NSRect(x: 20, y: 145, width: 460, height: 36))

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        add(spinner, frame: NSRect(x: 20, y: 20, width: 20, height: 20))

        mergeButton = NSButton(title: "Merge", target: self, action: #selector(merge))
        mergeButton.bezelStyle = .rounded
        mergeButton.keyEquivalent = "\r"
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
        destLabel.stringValue = url.path
        destLabel.textColor = .labelColor
        mergeButton.isEnabled = true
    }

    @objc private func merge() {
        guard let destination, !sources.isEmpty else { return }
        guard let script = Bundle.main.url(forResource: "mergefolders", withExtension: nil) else {
            statusLabel.stringValue = "This copy of Merge Folders is damaged: the mergefolders script is missing."
            return
        }

        mergeButton.isEnabled = false
        chooseButton.isEnabled = false
        spinner.startAnimation(nil)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Merging…"

        let arguments = ["--to", destination.path] + sources.map(\.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = script
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            var output = ""
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                output = "Could not start the merge: \(error.localizedDescription)"
            }

            Self.appendLog("$ mergefolders \(arguments.joined(separator: " "))\n\(output)\n")
            let failed = process.terminationStatus != 0

            DispatchQueue.main.async {
                self.spinner.stopAnimation(nil)
                self.chooseButton.isEnabled = true
                self.mergeButton.isEnabled = true
                self.statusLabel.textColor = failed ? .systemRed : .labelColor
                self.statusLabel.stringValue = output.isEmpty
                    ? (failed ? "The merge failed." : "Done.")
                    : output
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
                try? FileManager.default.removeItem(at: logURL)
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
