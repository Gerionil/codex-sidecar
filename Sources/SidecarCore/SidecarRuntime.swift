import Foundation
import Darwin

public enum ExecutableVersion {
    /// Bounded, cancellable, owned --version probe. Retains only a numeric version.
    public static func verify(_ executable: URL, root: URL, environment: [String: String]) async -> String? {
        let task = Task.detached(priority: .utility) { () -> String? in
            let process = Process(), output = Pipe(), errors = Pipe()
            process.executableURL = executable; process.arguments = ["--version"]
            var env = environment; env["CODEX_HOME"] = root.path; process.environment = env
            process.standardOutput = output; process.standardError = errors; process.standardInput = FileHandle.nullDevice
            defer {
                try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
                try? errors.fileHandleForReading.close(); try? errors.fileHandleForWriting.close()
            }
            for fd in [output.fileHandleForReading.fileDescriptor, errors.fileHandleForReading.fileDescriptor] {
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            }
            do { try process.run() } catch { return nil }
            try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
            let deadline = ProcessInfo.processInfo.systemUptime + 2
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            var exceeded = false
            repeat {
                let n = read(output.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                if n > 0 { if data.count + n <= 4096 { data.append(contentsOf: buffer.prefix(n)) } else { exceeded = true } }
                _ = read(errors.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                if exceeded || Task.isCancelled || ProcessInfo.processInfo.systemUptime >= deadline {
                    if process.isRunning { process.terminate(); _ = kill(process.processIdentifier, SIGKILL) }
                    process.waitUntilExit(); return nil
                }
                if !process.isRunning && n <= 0 { break }
                try? await Task.sleep(for: .milliseconds(10))
            } while true
            process.waitUntilExit()
            guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8),
                  let range = text.range(of: #"^codex-cli [0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?\s*$"#, options: .regularExpression) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "codex-cli ", with: "")
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
extension SidecarRuntime {
    public static func live(_ settings: LocalSettings) async -> SidecarRuntime {
        let environment = ProcessInfo.processInfo.environment
        let root = SessionCatalog.resolveRoot(override: settings.rootOverride.map { URL(fileURLWithPath: $0, isDirectory: true) },
                                              environment: environment, userHome: FileManager.default.homeDirectoryForCurrentUser)
        let executable = QuotaExecutable.resolve(override: settings.executableOverride.map { URL(fileURLWithPath: $0) }, environment: environment)
        let version: String?
        if let executable { version = await ExecutableVersion.verify(executable, root: root, environment: environment) }
        else { version = nil }
        let provider = QuotaProvider(offline: settings.offline) {
            guard let executable else { throw QuotaFailure.missingExecutable }
            guard version != nil else { throw QuotaFailure.unsupportedProtocol }
            return QuotaRPC(configuration: .init(executable: executable, root: root, environment: environment))
        }
        let compatibility: String
        if let version {
            compatibility = "Codex CLI \(version) · " + (version == "0.160.1" ? "Reference profile; capabilities checked by provider" : "Unvalidated version; capabilities checked by provider")
        } else { compatibility = executable == nil ? "Codex executable missing" : "Executable version verification failed" }
        return SidecarRuntime(root: root, catalog: SessionCatalog(), reader: SessionReader(root: root), quotas: provider, compatibility: compatibility)
    }
}
