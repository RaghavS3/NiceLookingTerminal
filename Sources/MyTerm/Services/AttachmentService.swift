import AppKit
import MyTermCore

final class AttachmentService {
    struct CopyResult {
        let insertedURLs: [URL]
        let failedNames: [String]
    }

    enum AttachmentError: LocalizedError {
        case imageEncodingFailed

        var errorDescription: String? {
            "The image could not be converted to PNG."
        }
    }

    private let store: AttachmentPathStore
    private let queue = DispatchQueue(label: "com.nicelookingterminal.attachments", qos: .userInitiated)

    init(store: AttachmentPathStore) {
        self.store = store
    }

    func copyFiles(_ urls: [URL], completion: @escaping (CopyResult) -> Void) {
        queue.async {
            let signpost = PerformanceTelemetry.begin("Attachment Copy")
            defer { PerformanceTelemetry.end("Attachment Copy", id: signpost) }
            var insertedURLs: [URL] = []
            var failedNames: [String] = []

            for source in urls {
                let accessedSecurityScope = source.startAccessingSecurityScopedResource()
                defer {
                    if accessedSecurityScope { source.stopAccessingSecurityScopedResource() }
                }
                do {
                    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                    let suffix = UUID().uuidString.prefix(8)
                    let filename = "drop_\(timestamp)_\(suffix)_\(source.lastPathComponent)"
                    let destination = try self.store.uniqueURL(
                        prefix: "drop",
                        originalName: filename,
                        fileExtension: source.pathExtension.isEmpty ? "file" : source.pathExtension
                    )
                    try FileManager.default.copyItem(at: source, to: destination)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                    insertedURLs.append(destination)
                } catch {
                    insertedURLs.append(source)
                    failedNames.append(source.lastPathComponent)
                }
            }

            DispatchQueue.main.async {
                completion(CopyResult(insertedURLs: insertedURLs, failedNames: failedNames))
            }
        }
    }

    func persistPNG(
        from image: NSImage,
        prefix: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let imageCopy = image.copy() as? NSImage else {
            completion(.failure(AttachmentError.imageEncodingFailed))
            return
        }

        queue.async {
            let signpost = PerformanceTelemetry.begin("Image Encoding")
            defer { PerformanceTelemetry.end("Image Encoding", id: signpost) }
            let result: Result<URL, Error>
            do {
                guard let tiffData = imageCopy.tiffRepresentation else {
                    throw AttachmentError.imageEncodingFailed
                }
                guard let bitmap = NSBitmapImageRep(data: tiffData),
                    let pngData = bitmap.representation(using: .png, properties: [:])
                else {
                    throw AttachmentError.imageEncodingFailed
                }
                let url = try self.store.uniqueURL(prefix: prefix, fileExtension: "png")
                try pngData.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                result = .success(url)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
