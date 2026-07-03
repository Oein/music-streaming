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
    showMainWindow()
  }

  // Bring back the app's real window (not the menu-bar status window). After a
  // close the window is only hidden (isReleasedWhenClosed = false), so ordering
  // it front reuses the same Flutter engine.
  private func showMainWindow() {
    let windows = NSApplication.shared.windows
    let target = windows.first { $0 is MainFlutterWindow }
      ?? windows.first { $0.contentViewController is FlutterViewController }
    if let window = target {
      window.makeKeyAndOrderFront(nil)
    }
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  // Clicking the Dock icon while no window is visible reopens the window.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
