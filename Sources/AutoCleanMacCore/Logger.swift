import Foundation

public final class Logger {
    private let directory: URL
    private let clock: () -> Date
    private let isoFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter
    private let queue = DispatchQueue(label: "autocleanmac.logger")

    public init(directory: URL, clock: @escaping () -> Date = Date.init) throws {
        self.directory = directory
        self.clock = clock
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.timeZone = TimeZone(identifier: "UTC")
        self.dayFormatter = DateFormatter()
        self.dayFormatter.timeZone = TimeZone(identifier: "UTC")
        self.dayFormatter.dateFormat = "yyyy-MM-dd"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func log(event: String, fields: [String: String] = [:]) {
        let now = clock()
        let timestamp = isoFormatter.string(from: now)
        let day = dayFormatter.string(from: now)
        let fieldsString = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "\(timestamp)\t\(event)\t\(fieldsString)\n"
        let file = directory.appendingPathComponent("\(day).log")
        queue.sync {
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
            }
        }
    }
}
