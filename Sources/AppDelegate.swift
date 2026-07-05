import Cocoa
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var playerView: PlayerView!
    private var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupWindow()

        // Priority: CLI argument > Finder-opened file > last played video.
        let args = CommandLine.arguments.dropFirst()
        if let path = args.first {
            playerView.load(url: URL(fileURLWithPath: path))
        } else if let pendingURL {
            playerView.load(url: pendingURL)
        } else if let lastPath = UserDefaults.standard.string(forKey: "lastVideoPath"),
                  FileManager.default.fileExists(atPath: lastPath) {
            playerView.load(url: URL(fileURLWithPath: lastPath))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Called when a video is opened via Finder ("Open With" / double-click / drag onto Dock icon).
    // Can arrive before applicationDidFinishLaunching, i.e. before the window exists.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if let playerView {
            playerView.load(url: url)
        } else {
            pendingURL = url
        }
        return true
    }

    private func setupWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 960, height: 600)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "LaPlayer"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 480, height: 320)
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        } else {
            window.center()
        }

        playerView = PlayerView(frame: contentRect)
        window.contentView = playerView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(playerView)
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit LaPlayer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument), keyEquivalent: "o")
        let closeItem = NSMenuItem(title: "Close", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = .control
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            playerView.load(url: url)
        }
    }
}
