import Foundation
import Darwin

enum ControlSocket {
    static var path: String { Paths.socket.path }
}

func unixAddress(_ path: String) -> sockaddr_un? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= capacity else { return nil }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
            for (index, byte) in bytes.enumerated() {
                destination[index] = byte
            }
        }
    }
    return address
}

final class ControlServer {
    private let path: String
    private let handler: (String) -> String
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    init?(handler: @escaping (String) -> String) {
        self.handler = handler
        path = ControlSocket.path

        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = unixAddress(path) else {
            if fd >= 0 { close(fd) }
            return nil
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            close(fd)
            unlink(path)
            return nil
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.resume()
        self.source = source
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        source?.cancel()
        source = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(path)
    }

    private func acceptConnection() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        let command = readCommand(clientFD)
        let response = handler(command) + "\n"
        _ = response.withCString { write(clientFD, $0, strlen($0)) }
        close(clientFD)
    }

    private func readCommand(_ fd: Int32) -> String {
        var data = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 256)
        while data.count <= 4096 {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
