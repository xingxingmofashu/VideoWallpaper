import ArgumentParser

struct VideoWallpaper: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vw",
        abstract: "Play a video as the desktop wallpaper.",
        version: Version.full,
        subcommands: [
            RunCommand.self,
            StopCommand.self,
            MuteCommand.self,
            UnmuteCommand.self,
            WaveformCommand.self,
            UninstallCommand.self,
            VersionCommand.self,
        ],
        defaultSubcommand: RunCommand.self)

    func run() throws {
        throw CleanExit.helpRequest(self)
    }
}
