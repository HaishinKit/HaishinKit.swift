import Foundation

enum TestEnvironment {
    static var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] == "true"
    }
}
