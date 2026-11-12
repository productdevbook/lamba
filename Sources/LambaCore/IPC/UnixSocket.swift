import Darwin
import Foundation

public enum SocketError: Error, CustomStringConvertible, Equatable {
    case pathTooLong(String)
    case system(call: String, errno: Int32)
    case emptyResponse

    /// True when nobody is listening on the socket (service not running).
    public var isNotRunning: Bool {
        if case let .system(call, code) = self, call == "connect" {
            return code == ENOENT || code == ECONNREFUSED
        }
        return false
    }

    public var description: String {
        switch self {
        case let .pathTooLong(path): return "Socket path is too long: \(path)"
        case let .system(call, code): return "\(call) failed: \(String(cString: strerror(code)))"
        case .emptyResponse: return "Empty response"
        }
    }
}

/// One request per connection, newline-delimited JSON. Small and dependency-free on purpose.
enum SocketIO {
    static let maxMessageSize = 64 * 1024

    static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw SocketError.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        address.sun_len = UInt8(length)
        return try withUnsafePointer(to: &address) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, length) }
        }
    }

    static func configure(_ fd: Int32, timeout: TimeInterval) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Reads up to the first newline (or EOF).
    static func readMessage(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < maxMessageSize {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw SocketError.system(call: "read", errno: errno)
            }
            if count == 0 { break }
            data.append(buffer, count: count)
            if let newline = data.firstIndex(of: 0x0A) {
                return Data(data[data.startIndex..<newline])
            }
        }
        return data
    }

    static func writeMessage(_ fd: Int32, _ message: Data) throws {
        var payload = message
        payload.append(0x0A)
        try payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw SocketError.system(call: "write", errno: errno)
                }
                offset += written
            }
        }
    }
}

public final class UnixSocketServer {
    public typealias Authorizer = (_ peerUID: uid_t) -> Bool
    public typealias Handler = (_ request: Data) -> Data
    /// Answers whenever it is ready by calling `reply` once (e.g. after the user decides).
    /// `peer` is the connecting process (for SSH-forwarded requests, the local `ssh` client).
    public typealias AsyncHandler = (_ request: Data, _ peer: Int32?, _ reply: @escaping (Data) -> Void) -> Void

    private let path: String
    private let source: DispatchSourceRead

    /// Starts listening immediately. Requests are handled serially on `queue`.
    public convenience init(
        path: String,
        permissions: mode_t,
        queue: DispatchQueue,
        authorize: @escaping Authorizer,
        handler: @escaping Handler
    ) throws {
        try self.init(path: path, permissions: permissions, queue: queue, authorize: authorize) { request, _, reply in
            reply(handler(request))
        }
    }

    /// Starts listening immediately. Each connection stays open until its reply is sent,
    /// so a slow answer doesn't block other clients.
    public init(
        path: String,
        permissions: mode_t,
        queue: DispatchQueue,
        authorize: @escaping Authorizer,
        asyncHandler: @escaping AsyncHandler
    ) throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(call: "socket", errno: errno) }
        do {
            try SocketIO.withAddress(path) { address, length in
                guard bind(fd, address, length) == 0 else { throw SocketError.system(call: "bind", errno: errno) }
            }
            guard chmod(path, permissions) == 0 else { throw SocketError.system(call: "chmod", errno: errno) }
            guard listen(fd, 16) == 0 else { throw SocketError.system(call: "listen", errno: errno) }
        } catch {
            close(fd)
            throw error
        }

        self.path = path
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            Self.serve(client, authorize: authorize, handler: asyncHandler)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit {
        source.cancel()
        unlink(path)
    }

    private static func serve(_ client: Int32, authorize: Authorizer, handler: AsyncHandler) {
        SocketIO.configure(client, timeout: 2)

        var uid = uid_t(0)
        var gid = gid_t(0)
        guard getpeereid(client, &uid, &gid) == 0, authorize(uid),
              let request = try? SocketIO.readMessage(client), !request.isEmpty else {
            close(client)
            return
        }
        handler(request, ProcessTree.peerPID(of: client)) { response in
            try? SocketIO.writeMessage(client, response)
            close(client)
        }
    }
}

public enum UnixSocketClient {
    public static func roundTrip(path: String, request: Data, timeout: TimeInterval = 3) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(call: "socket", errno: errno) }
        defer { close(fd) }
        SocketIO.configure(fd, timeout: timeout)

        try SocketIO.withAddress(path) { address, length in
            guard connect(fd, address, length) == 0 else { throw SocketError.system(call: "connect", errno: errno) }
        }
        try SocketIO.writeMessage(fd, request)
        let response = try SocketIO.readMessage(fd)
        guard !response.isEmpty else { throw SocketError.emptyResponse }
        return response
    }
}
