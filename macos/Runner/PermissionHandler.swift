import FlutterMacOS
import Foundation

class PermissionHandler: NSObject {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.example.flutter_cli_ui/permissions", binaryMessenger: registrar.messenger)
    let instance = PermissionHandler()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
}

extension PermissionHandler: FlutterPlugin {
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      requestPermission(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    let openPanel = NSOpenPanel()
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = false
    openPanel.allowsMultipleSelection = false
    openPanel.prompt = "Grant Access"

    openPanel.begin { (response) in
      if response == .OK {
        result(true)
      } else {
        result(false)
      }
    }
  }
}
