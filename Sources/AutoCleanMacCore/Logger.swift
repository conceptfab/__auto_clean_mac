import Foundation

public final class Logger: @unchecked Sendable {
    private let directory: URL
    private let clock: @Sendable () -> Date
    private let isoFormatter: ISO8601DateFormatter
    private let dayFormatter: DateFormatter
    private let queue = DispatchQueue(label: "autocleanmac.logger")
    /// Otwarty uchwyt do pliku bieżącego dnia (dostęp wyłącznie na `queue`).
    private var handle: FileHandle?
    private var handleDay: String?

    public init(directory: URL, clock: @escaping @Sendable () -> Date = { Date() }) throws {
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
        guard let data = line.data(using: .utf8) else { return }
        queue.sync {
            do {
                try currentHandle(day: day, file: file).write(contentsOf: data)
            } catch {
                // Uchwyt mógł się zepsuć (np. plik usunięty/odmontowany) — jedna próba z nowym.
                closeHandle()
                do {
                    try currentHandle(day: day, file: file).write(contentsOf: data)
                } catch {
                    closeHandle()
                    NSLog("AutoCleanMac.Logger: write failed for \(file.path): \(error)")
                }
            }
        }
    }

    deinit {
        try? handle?.close()
    }

    /// Wołać tylko na `queue`. Plik otwierany z `O_APPEND`, więc każdy zapis trafia na koniec
    /// nawet gdy do tego samego logu pisze równolegle drugi proces (aplikacja + hub).
    private func currentHandle(day: String, file: URL) throws -> FileHandle {
        if let handle, handleDay == day { return handle }
        closeHandle()
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: file.path])
        }
        let newHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle = newHandle
        handleDay = day
        return newHandle
    }

    private func closeHandle() {
        try? handle?.close()
        handle = nil
        handleDay = nil
    }
}
