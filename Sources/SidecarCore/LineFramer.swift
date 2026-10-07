import Foundation

/// Frames bytes before decoding UTF-8. Unterminated and oversized input is never decoded.
public struct LineFramer: Sendable {
    public static let maximumLineBytes = 8 * 1024 * 1024
    private var buffer = Data()
    private var discarding = false
    private var offset: Int64 = 0
    private var lineStart: Int64 = 0
    public private(set) var completedOffsets: [Int64] = []
    public private(set) var diagnostics: [SanitizedDiagnostic] = []
    public var bufferedByteCount: Int { buffer.count }
    public var hasIncompleteLine: Bool { discarding || !buffer.isEmpty }
    public init() {}

    public mutating func append(_ bytes: Data) -> [Data] {
        var lines: [Data] = []
        completedOffsets.removeAll(keepingCapacity: true)
        var start = bytes.startIndex
        while start < bytes.endIndex {
            let newline = bytes[start...].firstIndex(of: 10)
            let end = newline ?? bytes.endIndex
            let count = bytes.distance(from: start, to: end)
            if !discarding {
                if count > Self.maximumLineBytes - buffer.count {
                    buffer.removeAll(keepingCapacity: false)
                    discarding = true
                    let prior = diagnostics.first?.occurrenceCount ?? 0
                    diagnostics = [.init(category: .oversizedRecord, byteOffset: lineStart, occurrenceCount: prior + 1)]
                } else { buffer.append(contentsOf: bytes[start..<end]) }
            }
            offset += Int64(count)
            if let newline {
                if !discarding {
                    if buffer.last == 13 { buffer.removeLast() }
                    lines.append(buffer); completedOffsets.append(lineStart)
                }
                buffer = Data(); discarding = false
                offset += 1; lineStart = offset
                start = bytes.index(after: newline)
            } else { start = bytes.endIndex }
        }
        return lines
    }
    public mutating func takeDiagnostics() -> [SanitizedDiagnostic] {
        defer { diagnostics.removeAll() }
        return diagnostics
    }
    public mutating func reset() { self = LineFramer() }
}
