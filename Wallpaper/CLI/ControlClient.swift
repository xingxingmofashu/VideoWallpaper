import Foundation
import Darwin

enum ControlClient {
    static func send(_ command: String) -> Int32 {
        let path = ControlSocket.path
        guard FileManager.default.fileExists(atPath: path) else {
            Console.info("No running instance")
            return 0
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = unixAddress(path) else {
            Console.error("Failed to open the control socket")
            return 1
        }
        defer { close(fd) }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
        }
        guard connected == 0 else {
            Console.info("No running instance")
            return 0
        }

        _ = command.withCString { write(fd, $0, strlen($0)) }
        shutdown(fd, SHUT_WR)

        var data = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        let response = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        Console.info(response.isEmpty ? "Done" : response)
        return 0
    }
}
