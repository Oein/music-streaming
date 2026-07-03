import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var statusItem: NSStatusItem!

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem.button {
      if #available(macOS 11.0, *) {
        button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Music Player")
      } else {
        button.title = "♪"
      }
      button.action = #selector(statusBarClicked)
      button.target = self
    }
  }

  @objc func statusBarClicked() {
    if let window = NSApplication.shared.windows.first {
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
