import Foundation

enum Version {
    static let number = "1.2.0"
    static let name = "vw"
    static let full = "\(name) \(number)"
}

struct VersionCommand: Command {
    let name = "version"
    let summary = "Show version"

    func execute(arguments: [String]) -> Int32 {
        Console.info(Version.full)
        return 0
    }
}
