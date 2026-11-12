import Foundation

/// Anything that can execute app requests: the real socket client, or a fake in tests.
public protocol LambaService {
    func send(_ request: AppRequest) throws -> AppResponse
}

/// Talks to the running menu bar app.
public struct AppClient: LambaService {
    public var socketPath: String
    /// How long to wait for the answer; permission requests wait for the user.
    public var timeout: TimeInterval

    public init(socketPath: String = LambaPaths.appSocket, timeout: TimeInterval = 3) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    public func send(_ request: AppRequest) throws -> AppResponse {
        let data = try UnixSocketClient.roundTrip(path: socketPath, request: Wire.encode(request), timeout: timeout)
        return try Wire.decode(AppResponse.self, from: data)
    }
}

/// Talks to the root helper daemon.
public struct HelperClient {
    public var socketPath: String

    public init(socketPath: String = LambaPaths.helperSocket) {
        self.socketPath = socketPath
    }

    /// Fan changes can take a few seconds while macOS hands the fans over.
    public func send(_ request: HelperRequest, timeout: TimeInterval = 1) throws -> HelperResponse {
        let data = try UnixSocketClient.roundTrip(path: socketPath, request: Wire.encode(request), timeout: timeout)
        return try Wire.decode(HelperResponse.self, from: data)
    }
}
