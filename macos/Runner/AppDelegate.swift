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
      name: "com.example.dependency_manager/permissions",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "requestElevatedPermissions" {
        self.requestElevatedPermissions(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
  }

  private func requestElevatedPermissions(result: @escaping FlutterResult) {
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", "do shell script \"echo success\" with administrator privileges"]

    let outputPipe = Pipe()
    task.standardOutput = outputPipe

    task.launch()
    task.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8)

    if output?.trimmingCharacters(in: .whitespacesAndNewlines) == "success" {
      result(true)
    } else {
      result(false)
    }
  }
}
