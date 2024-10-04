import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller: FlutterViewController =
      mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.example.flutter_cli_ui/permissions",
      binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }

      if call.method == "pickDirectory" {
        self.pickDirectory(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.applicationDidFinishLaunching(notification)
  }

  private func pickDirectory(result: @escaping FlutterResult) {
    let openPanel = NSOpenPanel()
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = false
    openPanel.allowsMultipleSelection = false
    openPanel.prompt = "Select Folder"

    openPanel.begin { (response) in
      if response == .OK {
        if let url = openPanel.url {
          result(url.path)
        } else {
          result(FlutterError(code: "NO_DIRECTORY", message: "No directory selected", details: nil))
        }
      } else {
        result(
          FlutterError(code: "CANCELLED", message: "Directory selection cancelled", details: nil))
      }
    }
  }
}
