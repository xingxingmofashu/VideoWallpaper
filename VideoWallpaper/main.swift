import ArgumentParser
import Foundation

let arguments = CommandLine.arguments

if arguments.dropFirst().first == Daemon.flag {
    exit(DaemonEntry.run(Array(arguments.dropFirst(2))))
}

if arguments.dropFirst().first == "-v" {
    Console.info(Version.full)
    exit(0)
}

if arguments.count == 1 {
    VideoWallpaper.main(["--help"])
}

VideoWallpaper.main(Array(arguments.dropFirst()))
