import Foundation

struct HelpCommand: Command {
    let name = "help"
    let summary = "Show help"

    func execute(arguments: [String]) -> Int32 {
        Console.info(usage())
        return 0
    }

    func usage() -> String {
        var lines = [
            Version.full,
            "",
            "Usage:",
            "  \(Version.name) <command> [arguments]",
            "",
            "Commands:",
        ]
        for command in CLI.commands {
            let padded = command.name.padding(toLength: 10, withPad: " ", startingAt: 0)
            lines.append("  \(Version.name) \(padded) \(command.summary)")
        }
        lines.append("")
        if let run = CLI.commands.first(where: { $0.name == "run" }) as? RunCommand {
            lines.append(run.optionsHelp)
        }
        lines.append("")
        lines.append("Examples:")
        lines.append("  \(Version.name) run ~/Videos/wallpaper.mov")
        lines.append("  \(Version.name) run ~/Videos/wallpapers --shuffle")
        lines.append("  \(Version.name) run video.mov --single --rate 0.5")
        return lines.joined(separator: "\n")
    }
}
