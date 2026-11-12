import Foundation
import LambaCore

/// System sleep on/off (`pmset disablesleep`). Reading needs no rights; changing goes through the
/// root helper so there is no password prompt each time.
enum SystemSleep {
    /// `SleepDisabled 1` in `pmset -g`: the Mac never sleeps, even with the lid closed.
    static var isDisabled: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return output.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.count == 2 && fields[0] == "SleepDisabled" && fields[1] == "1"
        }
    }

    static func set(disabled: Bool) throws {
        let response = try HelperClient().send(.sleep(disabled: disabled))
        guard response.ok else { throw HelperError(message: response.error ?? "") }
    }

    struct HelperError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
