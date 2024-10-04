import Foundation

class FlutterHelper {
  static let shared = FlutterHelper()

  private init() {}

  lazy var flutterPath: String? = {
    return findFlutterPath()
  }()

  private func findFlutterPath() -> String? {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = ["which", "flutter"]

    let pipe = Pipe()
    task.standardOutput = pipe

    do {
      try task.run()
    } catch {
      print("Error: \(error.localizedDescription)")
      return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard
      let output = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
    else {
      return nil
    }

    return output.isEmpty ? nil : output
  }

  func runFlutterCommand(args: [String]) -> (output: String, exitCode: Int32) {
    guard let flutterPath = flutterPath else {
      print("Error: Flutter executable not found in PATH")
      return ("Flutter executable not found", 1)
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: flutterPath)
    task.arguments = args

    let outputPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = outputPipe

    do {
      try task.run()
    } catch {
      print("Error: \(error.localizedDescription)")
      return (error.localizedDescription, 1)
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8) ?? ""

    task.waitUntilExit()
    return (output, task.terminationStatus)
  }

  func pubGet(packagePath: String) -> (output: String, exitCode: Int32) {
    let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let packageURL = URL(fileURLWithPath: packagePath, relativeTo: currentDirectoryURL)

    FileManager.default.changeCurrentDirectoryPath(packageURL.path)
    defer { FileManager.default.changeCurrentDirectoryPath(currentDirectoryURL.path) }

    return runFlutterCommand(args: ["pub", "get"])
  }

  func pubUpgrade(packagePath: String, dependency: String? = nil) -> (
    output: String, exitCode: Int32
  ) {
    let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let packageURL = URL(fileURLWithPath: packagePath, relativeTo: currentDirectoryURL)

    FileManager.default.changeCurrentDirectoryPath(packageURL.path)
    defer { FileManager.default.changeCurrentDirectoryPath(currentDirectoryURL.path) }

    var args = ["pub", "upgrade"]
    if let dependency = dependency {
      args.append(dependency)
    }

    return runFlutterCommand(args: args)
  }
}
