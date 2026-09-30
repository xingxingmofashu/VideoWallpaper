import Foundation

enum CLI {
    static let commands: [any Command] = [
        RunCommand(),
        StopCommand(),
        MuteCommand(),
        UnmuteCommand(),
        UninstallCommand(),
        VersionCommand(),
        HelpCommand(),
    ]

    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count > 1 else {
            return HelpCommand().execute(arguments: [])
        }

        switch arguments[1] {
        case "-h", "--help":
            return HelpCommand().execute(arguments: [])
        case "-v", "--version":
            return VersionCommand().execute(arguments: [])
        default:
            if arguments[1] == Daemon.flag {
                return RunCommand().executeDaemon(arguments: Array(arguments.dropFirst(2)))
            }
            if let command = find(arguments[1]) {
                return command.execute(arguments: Array(arguments.dropFirst(2)))
            }
            if arguments[1].hasPrefix("-") {
                return HelpCommand().execute(arguments: [])
            }
            return RunCommand().execute(arguments: Array(arguments.dropFirst(1)))
        }
    }

    private static func find(_ name: String) -> (any Command)? {
        commands.first { $0.name == name }
    }
}
