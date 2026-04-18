import Foundation

public struct TestRobotWrapper {
    public static func runTestRobot() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "cells/fusion/macos/TestRobot/.build/debug/TestRobot")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    public static func runSwiftTestRobit() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "cells/health/swift_testrobit/.build/debug/SwiftTestRobit")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
