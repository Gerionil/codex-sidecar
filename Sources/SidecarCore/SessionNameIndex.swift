import Foundation
import Darwin

/// Optional metadata only. No transcript fallback, persistence, RPC or raw diagnostics.
struct SessionNameIndex {
    struct Entry {
        let title: String?
        let updatedAt: Date?
    }
    private struct Record: Decodable {
        let id: String
        let thread_name: String?
        let updated_at: String?
    }
    static func read(root: URL, sessionIDs: Set<String>) -> [String: Entry] {
        guard !sessionIDs.isEmpty else { return [:] }
        // Foundation can standardize a physical /private path back to a system alias.
        // Resolve only the approved root, never the index file itself (symlinks stay rejected).
        guard let physical = realpath(root.path, nil) else { return [:] }
        defer { free(physical) }
        let directory = URL(fileURLWithPath: String(cString: physical), isDirectory: true)
        let url = directory.appendingPathComponent("session_index.jsonl")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o400 != 0,
              let handle = try? SourceAccess.openFile(url) else { return [:] }
        defer { try? handle.close() }
        let ordinary = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let decoder = JSONDecoder()
        var framer = LineFramer(), entries: [String: Entry] = [:]
        var readBytes = 0
        let maximumBytes = 16 * 1024 * 1024
        do {
            while !Task.isCancelled {
                let chunk = try handle.read(upToCount: min(65536, maximumBytes - readBytes + 1)) ?? Data()
                if chunk.isEmpty { return entries } // Unterminated tail is intentionally ignored.
                readBytes += chunk.count
                // A truncated index could hide later renames, so fall back for the whole lookup.
                guard readBytes <= maximumBytes else { return [:] }
                for line in framer.append(chunk) {
                    guard let record = try? decoder.decode(Record.self, from: line),
                          record.id.utf8.count <= 256, sessionIDs.contains(record.id),
                          record.thread_name.map({ $0.utf8.count <= 4096 }) ?? true,
                          record.updated_at.map({ $0.utf8.count <= 64 }) ?? true else { continue }
                    let date = record.updated_at.flatMap { fractional.date(from: $0) ?? ordinary.date(from: $0) }
                    // Do not let a malformed recency field erase valid indexed metadata.
                    if record.updated_at != nil && date == nil { continue }
                    if let prior = entries[record.id],
                       (prior.updatedAt ?? .distantPast) > (date ?? .distantPast) { continue }
                    let title = record.thread_name.map {
                        $0.components(separatedBy: .whitespacesAndNewlines.union(.controlCharacters))
                            .filter { !$0.isEmpty }.joined(separator: " ")
                    }.flatMap { $0.isEmpty ? nil : $0 }
                    entries[record.id] = Entry(title: title, updatedAt: date)
                }
            }
        } catch { return [:] }
        return [:]
    }
}
