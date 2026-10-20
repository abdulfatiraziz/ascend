import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Photos attached to chat messages. Each is re-encoded on import, which drops EXIF/GPS metadata,
/// and stored under `<workspace>/attachments/<chat id>/`, outside tracker backups.
public enum ChatPhotos {
    public static let maxPerMessage = 4
    public static let maxSourceBytes = 40_000_000
    /// Claude's recommended longest edge; larger images are downscaled before sending.
    public static let maxPixelSize = 1568

    public static func folder(chat: UUID, workspace: URL) -> URL {
        workspace.appendingPathComponent("attachments", isDirectory: true).appendingPathComponent(chat.uuidString.lowercased(), isDirectory: true)
    }
    public static func isImage(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false)
    }
    /// Downscales and re-encodes a readable image (PNG when it has transparency, otherwise JPEG). Returns the stored file name.
    public static func store(_ source: URL, in folder: URL, maxPixel: Int = maxPixelSize) throws -> String {
        let name = source.lastPathComponent
        if let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxSourceBytes {
            throw ValidationError(message: "“\(name)” is larger than 40 MB. Choose a smaller photo.")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true]
        guard let reader = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(reader) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(reader, 0, options as CFDictionary) else {
            throw ValidationError(message: "“\(name)” isn’t a readable image.")
        }
        let alpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type: UTType = alpha ? .png : .jpeg
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stored = "\(UUID().uuidString.lowercased()).\(alpha ? "png" : "jpg")"
        let url = folder.appendingPathComponent(stored)
        guard let writer = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ValidationError(message: "“\(name)” could not be saved.")
        }
        CGImageDestinationAddImage(writer, image, (alpha ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.85]) as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw ValidationError(message: "“\(name)” could not be saved.") }
        return stored
    }
    public static func mediaType(_ file: URL) -> String { file.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg" }
}
