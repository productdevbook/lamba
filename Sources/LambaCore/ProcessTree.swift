import Darwin
import Foundation

/// Walks a process's ancestors (via sysctl), with each one's controlling terminal.
public enum ProcessTree {
    public struct Process: Equatable {
        public let pid: Int32
        public let tty: String?
    }

    /// `pid` itself first, then its parent, … up to (not including) launchd.
    public static func ancestors(of pid: Int32, limit: Int = 32) -> [Process] {
        var result: [Process] = []
        var current = pid
        while current > 1, result.count < limit {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { break }
            let device = info.kp_eproc.e_tdev
            let tty = device != -1 ? devname(device, S_IFCHR).map { "/dev/" + String(cString: $0) } : nil
            result.append(Process(pid: current, tty: tty))
            current = info.kp_eproc.e_ppid
        }
        return result
    }

    /// The process on the other end of a connected Unix domain socket.
    public static func peerPID(of socket: Int32) -> Int32? {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else { return nil }
        return pid
    }
}
