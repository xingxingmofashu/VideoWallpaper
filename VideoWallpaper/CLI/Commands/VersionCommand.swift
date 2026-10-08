import ArgumentParser

enum Version {
    static let number = "1.5.0"
    static let name = "vw"
    static let full = "\(name) \(number)"
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show version")

    func run() {
        Console.info(Version.full)
    }
}
