import Foundation

public final class TranscriptRecorder {
    public typealias FailureHandler = (Error) -> Void

    private let queue = DispatchQueue(label: "com.nicelookingterminal.transcript", qos: .utility)
    private let rawHandle: FileHandle
    private let textHandle: FileHandle
    private let failureHandler: FailureHandler
    private let stateLock = NSLock()
    private var pendingData = Data()
    private var drainScheduled = false
    private var acceptingData = true
    private var closeScheduled = false
    private var failed = false
    private var bytesSinceSync = 0
    private let maximumPendingBytes = 16 * 1_048_576

    public init(directory: URL, title: String, failureHandler: @escaping FailureHandler) throws {
        self.failureHandler = failureHandler
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let rawURL = directory.appendingPathComponent("terminal.raw")
        let textURL = directory.appendingPathComponent("transcript.txt")
        let metadataURL = directory.appendingPathComponent("metadata.json")
        for url in [rawURL, textURL] {
            fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }

        let metadata: [String: Any] = [
            "title": title,
            "startedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: metadataURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)

        rawHandle = try FileHandle(forWritingTo: rawURL)
        textHandle = try FileHandle(forWritingTo: textURL)
    }

    public func append(_ data: Data) {
        guard !data.isEmpty else { return }
        stateLock.lock()
        guard acceptingData else {
            stateLock.unlock()
            return
        }
        if pendingData.count + data.count > maximumPendingBytes {
            acceptingData = false
            stateLock.unlock()
            reportFailure(TranscriptRecorderError.backpressureLimitExceeded)
            return
        }
        pendingData.append(data)
        let shouldSchedule = !drainScheduled
        drainScheduled = true
        stateLock.unlock()

        if shouldSchedule {
            queue.async {
                self.drain()
            }
        }
    }

    public func close(completion: (() -> Void)? = nil) {
        stateLock.lock()
        acceptingData = false
        let shouldCloseHandles = !closeScheduled
        closeScheduled = true
        stateLock.unlock()
        queue.async {
            if shouldCloseHandles {
                try? self.rawHandle.synchronize()
                try? self.textHandle.synchronize()
                try? self.rawHandle.close()
                try? self.textHandle.close()
            }
            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    private func write(_ data: Data) {
        guard !failed else { return }
        do {
            try rawHandle.write(contentsOf: data)
            try textHandle.write(contentsOf: data)
            bytesSinceSync += data.count
            if bytesSinceSync >= 1_048_576 {
                try rawHandle.synchronize()
                try textHandle.synchronize()
                bytesSinceSync = 0
            }
        } catch {
            failed = true
            reportFailure(error)
        }
    }

    private func drain() {
        while true {
            stateLock.lock()
            guard !pendingData.isEmpty else {
                drainScheduled = false
                stateLock.unlock()
                return
            }
            let batch = pendingData
            pendingData.removeAll(keepingCapacity: true)
            stateLock.unlock()
            write(batch)
        }
    }

    private func reportFailure(_ error: Error) {
        DispatchQueue.main.async { [failureHandler] in
            failureHandler(error)
        }
    }
}

private enum TranscriptRecorderError: LocalizedError {
    case backpressureLimitExceeded

    var errorDescription: String? {
        "Transcript recording could not keep up with terminal output and was stopped before memory usage became unsafe."
    }
}
