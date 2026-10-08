import Foundation

enum Paths {
    static let app = "vw"

    static var home: URL {
        if let override = ProcessInfo.processInfo.environment["VW_TEST_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var data: URL { root("XDG_DATA_HOME", ".local/share") }
    static var state: URL { root("XDG_STATE_HOME", ".local/state") }
    static var config: URL { root("XDG_CONFIG_HOME", ".config") }
    static var cache: URL { root("XDG_CACHE_HOME", ".cache") }

    static var binaryDirectory: URL {
        home.appendingPathComponent(".vw", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    static var binary: URL { binaryDirectory.appendingPathComponent(app) }

    static var log: URL { data.appendingPathComponent("vw.log") }
    static var pid: URL { state.appendingPathComponent("vw.pid") }
    static var lock: URL { state.appendingPathComponent("vw.lock") }
    static var socket: URL { state.appendingPathComponent("vw.sock") }

    static func createDirectory(_ url: URL, permissions: Int? = nil) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private static func root(_ variable: String, _ fallback: String) -> URL {
        let base: URL
        if let value = ProcessInfo.processInfo.environment[variable], !value.isEmpty {
            base = URL(fileURLWithPath: value, isDirectory: true)
        } else {
            base = fallback.split(separator: "/").reduce(home) { url, component in
                url.appendingPathComponent(String(component), isDirectory: true)
            }
        }
        return base.appendingPathComponent(app, isDirectory: true)
    }
}

enum Project {
    static let repository = "xingxingmofashu/VideoWallpaper"
    static let installerURL = "https://raw.githubusercontent.com/\(repository)/main/Scripts/install.sh"
    static let latestReleaseURL = "https://api.github.com/repos/\(repository)/releases/latest"
}
