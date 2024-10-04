//
//  main.swift
//  FlutterHelper
//
//  Created by Antonio on 5/10/24.
//
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

  func runFlutterCommand(args: [String]) -> Int32 {
    guard let flutterPath = flutterPath else {
      print("Error: Flutter executable not found in PATH")
      return 1
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: flutterPath)
    task.arguments = args

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
    } catch {
      print("Error: \(error.localizedDescription)")
      return 1
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
      print(output)
    }

    task.waitUntilExit()
    return task.terminationStatus
  }
}

// Main execution
let args = Array(CommandLine.arguments.dropFirst())
exit(FlutterHelper.shared.runFlutterCommand(args: args))
