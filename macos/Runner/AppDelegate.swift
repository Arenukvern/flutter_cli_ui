import Cocoa
import FlutterMacOS
import Foundation

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard
      let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      print("Error: Unable to get FlutterViewController")
      return
    }

    let channel = FlutterMethodChannel(
      name: "com.example.flutter_cli_ui/flutter_helper",
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    channel.setMethodCallHandler {
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      do {
        print("Received method call: \(call.method)")
        print("Arguments: \(String(describing: call.arguments))")

        switch call.method {
        case "runPubGet":
          try self?.runPubGet(call, result: result)
        case "runPubUpgrade":
          try self?.runPubUpgrade(call, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        print("Error in method call handler: \(error)")
        result(
          FlutterError(code: "UNEXPECTED_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func getFlutterHelperPath() -> String? {
    guard let helperURL = Bundle.main.url(forResource: "FlutterHelper", withExtension: "") else {
      print("Error: FlutterHelper not found in bundle")
      return nil
    }
    return helperURL.path
  }

  private func runFlutterHelper(args: [String]) throws -> (output: String, exitCode: Int32) {
    guard let helperPath = getFlutterHelperPath() else {
      throw NSError(
        domain: "FlutterHelperError", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "FlutterHelper not found"])
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: helperPath)
    task.arguments = args

    let outputPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = outputPipe

    do {
      try task.run()
    } catch {
      print("Error running FlutterHelper: \(error)")
      throw error
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8) ?? ""

    task.waitUntilExit()
    return (output, task.terminationStatus)
  }

  private func runPubGet(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    guard let args = call.arguments as? [String: Any],
      let packagePath = args["packagePath"] as? String
    else {
      throw NSError(
        domain: "InvalidArgumentsError", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid arguments for runPubGet"])
    }

    let (output, exitCode) = try runFlutterHelper(args: ["pub", "get", packagePath])
    let response = ["output": output, "exitCode": exitCode] as [String: Any]
    print("Response: \(response)")
    result(response)
  }

  private func runPubUpgrade(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    guard let args = call.arguments as? [String: Any],
      let packagePath = args["packagePath"] as? String
    else {
      throw NSError(
        domain: "InvalidArgumentsError", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid arguments for runPubUpgrade"])
    }

    var helperArgs = ["pub", "upgrade", packagePath]
    if let dependency = args["dependency"] as? String {
      helperArgs.append(dependency)
    }

    let (output, exitCode) = try runFlutterHelper(args: helperArgs)
    let response = ["output": output, "exitCode": exitCode] as [String: Any]
    print("Response: \(response)")
    result(response)
  }
}
