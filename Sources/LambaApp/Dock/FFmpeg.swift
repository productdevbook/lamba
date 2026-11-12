import AVFoundation
import Foundation

/// AV1 and VP9 need software encoders macOS doesn't ship; Homebrew's ffmpeg has them. Used only
/// when it's installed, and never bundled.
enum FFmpeg {
    static let path: String? = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Encoder names, read once (in the background at first use is fine: it takes ~50 ms).
    static let encoders: Set<String> = {
        guard let path else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-hide_banner", "-encoders"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Set(String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ")
            return parts.count > 1 ? String(parts[1]) : nil
        })
    }()

    static func convert(_ source: URL, to output: URL, preset: MediaConverter.VideoPreset, progress: @escaping (Double) -> Void) async -> Result<Int64, Error> {
        guard let path else { return .failure(Failure(errorDescription: "ffmpeg not found")) }
        let duration = (try? await AVURLAsset(url: source).load(.duration)).map(CMTimeGetSeconds) ?? 0
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return .failure(error)
        }
        // Up to 1080p, keeps the aspect ratio and never upscales.
        let scale = "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"
        var arguments = ["-hide_banner", "-nostdin", "-y", "-i", source.path, "-vf", scale, "-progress", "pipe:1", "-nostats"]
        switch preset {
        case .webm:
            arguments += ["-c:v", "libvpx-vp9", "-crf", "33", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus", "-b:a", "96k"]
        default:
            arguments += ["-c:v", "libsvtav1", "-crf", "34", "-preset", "8", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]
        }
        arguments.append(output.path)

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let text = String(decoding: handle.availableData, as: UTF8.self)
                guard duration > 0 else { return }
                for line in text.split(separator: "\n") where line.hasPrefix("out_time_us=") {
                    if let micros = Double(line.dropFirst("out_time_us=".count)) {
                        progress(min(max(micros / 1_000_000 / duration, 0), 1))
                    }
                }
            }
            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(MediaConverter.fileSize(output)))
                } else {
                    try? FileManager.default.removeItem(at: output)
                    continuation.resume(returning: .failure(Failure(errorDescription: "ffmpeg failed (\(process.terminationStatus))")))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(error))
            }
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }
}
